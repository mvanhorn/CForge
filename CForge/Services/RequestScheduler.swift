import Foundation

/// Global actor-based scheduler to enforce Codeforces API rate limits.
/// Enforces a strict 1 request per 2 seconds limit across the entire app.
///
/// All network calls in ContestService, ProfileService, and ProblemService
/// route through this scheduler to prevent HTTP 429 responses from the
/// Codeforces API. Using a global actor ensures the rate limit is respected
/// even when multiple independent callers fire simultaneously.
actor RequestScheduler {
    static let shared = RequestScheduler()

    // MARK: - State

    private var lastRequestTime: Date = .distantPast
    private let minimumInterval: TimeInterval = 2.0  // Codeforces enforces 1 req / 2s

    // MARK: - API

    /// Schedules a network operation to respect the global rate limit.
    /// Callers block (suspend) until the slot is available — they are NOT dropped.
    /// - Parameter operation: The async throwing block to execute.
    /// - Returns: The result of the operation.
    func schedule<T>(operation: @escaping () async throws -> T) async throws -> T {
        // 1. Calculate wait time since last request
        let now = Date()
        let elapsed = now.timeIntervalSince(lastRequestTime)

        if elapsed < minimumInterval {
            let waitTime = minimumInterval - elapsed
            AppLog.debug(
                "Rate Limit: Waiting \(String(format: "%.2f", waitTime))s before next request",
                category: .network
            )
            try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
        }

        // 2. Reserve the slot BEFORE executing (conservative — counts start of request)
        lastRequestTime = Date()

        // 3. Execute
        return try await operation()
    }
}
