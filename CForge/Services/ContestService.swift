import Foundation

// MARK: - Protocol

protocol ContestServiceProtocol {
    func fetchUpcomingContests() async throws -> [CFContest]
}

// MARK: - Implementation

final class ContestService: ContestServiceProtocol {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchUpcomingContests() async throws -> [CFContest] {
        guard let url = URL(string: "https://codeforces.com/api/contest.list") else {
            throw NetworkError.invalidURL
        }

        AppLog.debug("Fetching contest list", category: .network)

        let (data, response) = try await RequestScheduler.shared.schedule {
            try await self.session.data(from: url)
        }

        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.transportError(
                wrapped: NSError(domain: "InvalidResponse", code: 0)
            )
        }
        guard (200...299).contains(http.statusCode) else {
            throw NetworkError.serverError(statusCode: http.statusCode)
        }

        do {
            let decoded = try JSONDecoder().decode(ContestResponse.self, from: data)
            guard decoded.status == "OK" else {
                let message = decoded.comment ?? "Unknown API error"
                AppLog.error("Contest API error: \(message)", category: .network)
                throw NetworkError.apiError(message: message)
            }
            let upcoming = (decoded.result ?? []).filter { $0.phase == "BEFORE" }
            AppLog.debug("Fetched \(upcoming.count) upcoming contests", category: .network)
            return upcoming
        } catch let error as NetworkError {
            throw error
        } catch {
            AppLog.error("Decoding error: \(error)", category: .network)
            throw NetworkError.decodingError(wrapped: error)
        }
    }
}
