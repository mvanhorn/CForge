import Foundation
import Combine

// MARK: - SubmissionRepository
//
// Actor-based single source of truth for submission data.
//
// Responsibilities:
//  - 30-second TTL in-memory cache per (handle, contestId) pair
//  - In-flight deduplication: concurrent fetches for the same key join the same Task
//  - WebSocket integration: listens for .submissionVerdict events, throttles at 500 ms,
//    prepends live verdicts to the cache and republishes via verdictReceived
//
// The 30s TTL is intentionally short because submission verdicts change after judging.

actor SubmissionRepository {

    // MARK: - Cache

    private struct CacheKey: Hashable {
        let handle: String
        let contestId: Int
    }

    private struct CacheEntry {
        var submissions: [Submission]
        var fetchTime: Date
    }

    private enum CacheTTL {
        static let submissions: TimeInterval = 30   // verdicts are time-sensitive
    }

    private var cache: [CacheKey: CacheEntry] = [:]
    private var ongoingTasks: [CacheKey: Task<[Submission], Error>] = [:]

    // MARK: - Services

    private let service: ProblemServiceProtocol
    private let wsService: WebSocketServiceProtocol

    // MARK: - Publishers

    private let _verdictReceived = PassthroughSubject<Submission, Never>()
    private var wsTask: Task<Void, Never>?

    nonisolated var verdictReceived: AnyPublisher<Submission, Never> {
        _verdictReceived.eraseToAnyPublisher()
    }

    // MARK: - Init

    init(
        service: ProblemServiceProtocol = ProblemService(),
        wsService: WebSocketServiceProtocol = LiveWebSocketService()
    ) {
        self.service = service
        self.wsService = wsService
        bindWebSocketEvents()
    }

    // MARK: - Fetch

    /// Fetches contest submissions for a given handle.
    /// Serves from the 30-second TTL cache; concurrent callers share the same in-flight Task.
    func getContestSubmissions(
        contestId: Int,
        handle: String,
        forceRefresh: Bool = false
    ) async throws -> [Submission] {
        let key = CacheKey(handle: handle, contestId: contestId)

        // Cache hit
        if !forceRefresh,
           let entry = cache[key],
           Date().timeIntervalSince(entry.fetchTime) < CacheTTL.submissions {
            AppLog.debug("SubmissionRepository: Cache hit for \(handle)/\(contestId)", category: .cache)
            return entry.submissions
        }

        // In-flight deduplication
        if let ongoing = ongoingTasks[key] {
            AppLog.debug("SubmissionRepository: Joining ongoing fetch for \(handle)/\(contestId)", category: .network)
            return try await ongoing.value
        }

        let task = Task<[Submission], Error> {
            do {
                let submissions = try await self.service.fetchContestSubmissions(
                    contestId: contestId,
                    handle: handle
                )
                let entry = CacheEntry(submissions: submissions, fetchTime: Date())
                self.cache[key] = entry
                self.ongoingTasks.removeValue(forKey: key)
                AppLog.debug("SubmissionRepository: Fetched \(submissions.count) submissions", category: .network)
                return submissions
            } catch {
                self.ongoingTasks.removeValue(forKey: key)
                throw error
            }
        }

        ongoingTasks[key] = task
        return try await task.value
    }

    // MARK: - WebSocket Binding

    private func bindWebSocketEvents() {
        wsTask = Task { [weak wsService, weak self] in
            guard let wsService else { return }
            var cancellables = Set<AnyCancellable>()

            // Throttle verdict events at 500 ms — prevents UI stutter during judge queue flushes.
            wsService.events
                .compactMap { event -> Submission? in
                    if case .submissionVerdict(let s) = event { return s } else { return nil }
                }
                .throttle(for: .milliseconds(500), scheduler: DispatchQueue.main, latest: true)
                .sink { [weak self] submission in
                    Task {
                        // Prepend the live verdict to every cache key matching this handle
                        await self?.prependToCache(submission: submission)
                        await self?._verdictReceived.send(submission)
                    }
                }
                .store(in: &cancellables)

            try? await Task.sleep(nanoseconds: .max)
        }
    }

    /// Inserts the incoming live verdict at the front of all cache entries for its author.
    private func prependToCache(submission: Submission) {
        let handle = submission.author.members.first?.handle ?? ""
        guard !handle.isEmpty else { return }

        for key in cache.keys where key.handle == handle {
            var entry = cache[key]!
            // Avoid duplicates — if the same submission id already exists, replace it
            entry.submissions.removeAll { $0.id == submission.id }
            entry.submissions.insert(submission, at: 0)
            cache[key] = entry
        }

        AppLog.debug("SubmissionRepository: Live verdict prepended for \(handle)", category: .cache)
    }
}
