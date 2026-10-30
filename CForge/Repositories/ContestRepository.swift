import Foundation
import Combine
import SwiftData

// MARK: - ContestRepository

/// Actor-based repository that is the single source of truth for contest data.
/// It merges REST responses (initial load / pull-to-refresh) with real-time
/// WebSocket events (live standings, rating updates).
///
/// Architecture note: The repository owns the WebSocket subscription so that
/// ViewModels remain stateless w.r.t. connection management. Throttling of
/// high-frequency events is applied here — at the repository boundary —
/// before any data reaches the ViewModel or UI.
actor ContestRepository {

    // MARK: - Cache Policy

    private enum CachePolicy {
        static let contestListTTL: TimeInterval = 300  // 5 minutes
    }

    // MARK: - REST State

    private let restService: ContestServiceProtocol
    private var cachedContests: [CFContest]?
    private var contestsFetchTime: Date?
    private var ongoingFetchTask: Task<[CFContest], Error>?

    // MARK: - Persistence

    private let modelContext: ModelContext

    // MARK: - WebSocket State

    private let wsService: WebSocketServiceProtocol
    private var wsTask: Task<Void, Never>?

    // MARK: - Published Outputs (via AsyncStream bridge)
    // These subjects are internal; ViewModels observe via async sequences.

    private let _standingsUpdated = PassthroughSubject<(Int, [StandingsRow]), Never>()
    private let _verdictReceived = PassthroughSubject<Submission, Never>()
    private let _connectionStateChanged = PassthroughSubject<WebSocketConnectionState, Never>()
    private let _dataLastUpdated = CurrentValueSubject<Date?, Never>(nil)

    nonisolated var standingsUpdated: AnyPublisher<(Int, [StandingsRow]), Never> {
        _standingsUpdated.eraseToAnyPublisher()
    }
    nonisolated var verdictReceived: AnyPublisher<Submission, Never> {
        _verdictReceived.eraseToAnyPublisher()
    }
    nonisolated var wsConnectionState: AnyPublisher<WebSocketConnectionState, Never> {
        _connectionStateChanged.eraseToAnyPublisher()
    }
    /// Emits the timestamp of the last successful data refresh (network or persisted).
    /// Nil until the first data is served. ViewModels use this to drive the staleness banner.
    nonisolated var dataLastUpdated: AnyPublisher<Date?, Never> {
        _dataLastUpdated.eraseToAnyPublisher()
    }

    // MARK: - Init

    init(
        restService: ContestServiceProtocol = ContestService(),
        wsService: WebSocketServiceProtocol = LiveWebSocketService(),
        modelContainer: ModelContainer = PersistenceController.shared.container
    ) {
        self.restService = restService
        self.wsService = wsService
        self.modelContext = ModelContext(modelContainer)
        bindWebSocketEvents()
    }

    // MARK: - REST: Fetch Upcoming Contests

    func getUpcomingContests(forceRefresh: Bool = false) async throws -> [CFContest] {
        // 1. Serve from SwiftData immediately — offline-first cold launch path
        if !forceRefresh {
            let persisted = (try? modelContext.fetch(FetchDescriptor<PersistedContest>())) ?? []
            let upcoming = persisted
                .filter { $0.phase == "BEFORE" }
                .map { $0.toDomain() }
                .sorted { ($0.startTimeSeconds ?? 0) < ($1.startTimeSeconds ?? 0) }
            if !upcoming.isEmpty {
                AppLog.debug("ContestRepository: \(upcoming.count) contests from SwiftData", category: .cache)
                // Report the most-recent persisted timestamp to drive the staleness banner
                let lastSaved = persisted.map { $0.updatedAt }.max() ?? Date()
                _dataLastUpdated.send(lastSaved)
                // Background refresh if in-memory cache is stale
                if isCacheStale() {
                    Task { try? await self.refreshInBackground() }
                }
                return upcoming
            }
        }

        // 2. In-memory TTL cache
        if !forceRefresh, let cached = cachedContests, let fetchTime = contestsFetchTime {
            if Date().timeIntervalSince(fetchTime) < CachePolicy.contestListTTL {
                AppLog.debug("ContestRepository: Returning cached contests", category: .cache)
                return cached
            }
        }

        // 3. Network fetch + deduplicate in-flight + persist
        if let ongoing = ongoingFetchTask {
            AppLog.debug("ContestRepository: Joining ongoing fetch task", category: .network)
            return try await ongoing.value
        }

        let task = Task<[CFContest], Error> {
            do {
                let contests = try await self.restService.fetchUpcomingContests()
                for contest in contests {
                    self.modelContext.insert(PersistedContest(from: contest))
                }
                try? self.modelContext.save()
                self._dataLastUpdated.send(Date())
                self.cachedContests = contests
                self.contestsFetchTime = Date()
                self.ongoingFetchTask = nil
                AppLog.debug("ContestRepository: Fetched \(contests.count) contests", category: .cache)
                return contests
            } catch {
                self.ongoingFetchTask = nil
                throw error
            }
        }

        ongoingFetchTask = task
        return try await task.value
    }

    // MARK: - Private Persistence Helpers

    private func isCacheStale() -> Bool {
        guard let fetchTime = contestsFetchTime else { return true }
        return Date().timeIntervalSince(fetchTime) >= CachePolicy.contestListTTL
    }

    private func refreshInBackground() async throws {
        let contests = try await restService.fetchUpcomingContests()
        for contest in contests {
            modelContext.insert(PersistedContest(from: contest))
        }
        try? modelContext.save()
        _dataLastUpdated.send(Date())
        cachedContests = contests
        contestsFetchTime = Date()
        AppLog.debug("ContestRepository: Background refresh complete", category: .cache)
    }

    // MARK: - WebSocket: Subscribe to Live Contest

    func subscribeToLiveContest(contestId: Int) {
        // NOTE: CForge is a tracker app — users do not submit from the phone.
        // Live verdict push is forward-looking infrastructure pending an official
        // Codeforces push API or a custom BFF proxy. Placeholder URL below.
        guard let url = URL(string: "wss://api.cforge.app/ws/contest/\(contestId)") else { return }
        wsService.connect(to: url)
    }

    func disconnectFromLiveContest() {
        wsService.disconnect()
    }

    // MARK: - WebSocket Binding

    private func bindWebSocketEvents() {
        wsTask = Task { [weak wsService, weak self] in
            guard let wsService else { return }

            // NOTE: SwiftData upsert on standingsUpdated is deferred — no `standingsUpdated`
            // WebSocket event exists yet (requires a BFF proxy). When the event is available,
            // update PersistedContest fields here and call modelContext.save().
            var cancellables = Set<AnyCancellable>()

            wsService.events
                .compactMap { event -> Submission? in
                    if case .submissionVerdict(let s) = event { return s } else { return nil }
                }
                .throttle(for: .milliseconds(500), scheduler: DispatchQueue.main, latest: true)
                .sink { [weak self] submission in
                    Task { await self?._verdictReceived.send(submission) }
                }
                .store(in: &cancellables)

            wsService.connectionState
                .sink { [weak self] state in
                    Task { await self?._connectionStateChanged.send(state) }
                }
                .store(in: &cancellables)

            // Keep the task alive by waiting indefinitely (cancelled via wsTask?.cancel())
            try? await Task.sleep(nanoseconds: .max)
        }
    }
}

// MARK: - StandingsRow (Domain Model)

struct StandingsRow: Identifiable, Equatable {
    let id: String  // handle
    let handle: String
    let rank: Int
    let points: Double
    let penalty: Int
}
