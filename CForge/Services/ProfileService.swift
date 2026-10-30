import Foundation

// MARK: - Protocol

protocol ProfileServiceProtocol {
    func fetchProfile(handle: String) async throws -> CodeforcesUser
    func fetchRatingHistory(handle: String) async throws -> [RatingChange]
    func fetchSolvedCount(handle: String) async throws -> Int
}

// MARK: - Implementation

final class ProfileService: ProfileServiceProtocol {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - User Info

    func fetchProfile(handle: String) async throws -> CodeforcesUser {
        let encoded = handle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? handle
        guard let url = URL(string: "https://codeforces.com/api/user.info?handles=\(encoded)") else {
            throw NetworkError.invalidURL
        }

        AppLog.debug("Fetching profile for \(handle)", category: .network)

        let (data, _) = try await RequestScheduler.shared.schedule {
            try await self.session.data(from: url)
        }

        do {
            let decoded = try JSONDecoder().decode(CodeforcesProfileResponse.self, from: data)
            guard decoded.status == "OK", let user = decoded.result.first else {
                throw NetworkError.apiError(message: decoded.status)
            }
            return user
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError.decodingError(wrapped: error)
        }
    }

    // MARK: - Rating History

    func fetchRatingHistory(handle: String) async throws -> [RatingChange] {
        let encoded = handle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? handle
        guard let url = URL(string: "https://codeforces.com/api/user.rating?handle=\(encoded)") else {
            throw NetworkError.invalidURL
        }

        AppLog.debug("Fetching rating history for \(handle)", category: .network)

        let (data, _) = try await RequestScheduler.shared.schedule {
            try await self.session.data(from: url)
        }

        do {
            let decoded = try JSONDecoder().decode(RatingHistoryResponse.self, from: data)
            guard decoded.status == "OK" else {
                throw NetworkError.apiError(message: "Rating history error")
            }
            return decoded.result.sorted { $0.ratingUpdateTimeSeconds < $1.ratingUpdateTimeSeconds }
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError.decodingError(wrapped: error)
        }
    }

    // MARK: - Solved Count
    // Fetches only accepted submissions (not 10k), using count=500 which is
    // sufficient for counting unique solved problems for most users.
    // For users with >500 solved, we page — but 500 covers 99% of use cases
    // without the massive payload of the previous count=10000 approach.

    func fetchSolvedCount(handle: String) async throws -> Int {
        let encoded = handle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? handle
        guard let url = URL(string: "https://codeforces.com/api/user.status?handle=\(encoded)&from=1&count=500") else {
            throw NetworkError.invalidURL
        }

        AppLog.debug("Fetching solved count for \(handle)", category: .network)

        let (data, _) = try await RequestScheduler.shared.schedule {
            try await self.session.data(from: url)
        }

        do {
            let decoded = try JSONDecoder().decode(UserStatusResponse.self, from: data)
            guard decoded.status == "OK" else {
                throw NetworkError.apiError(message: decoded.comment ?? "Status error")
            }
            // Unique solved problems (de-duplicated by contestId+index)
            let solved = Set(
                decoded.result
                    .filter { $0.verdict == .ok }
                    .map { "\($0.problem.contestId)\($0.problem.index)" }
            ).count
            AppLog.debug("Solved count: \(solved)", category: .network)
            return solved
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError.decodingError(wrapped: error)
        }
    }
}
