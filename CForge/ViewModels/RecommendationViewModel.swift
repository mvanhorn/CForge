import SwiftUI
import Combine

@MainActor
final class RecommendationViewModel: ObservableObject {

    enum ViewState {
        case idle
        case loading
        case loaded([ScoredProblem])
        case error(String)
    }

    @Published private(set) var state: ViewState = .idle

    private let profileRepository: ProfileRepository
    private let problemRepository: ProblemRepository
    private let service: ProblemService

    init() {
        self.profileRepository = ProfileRepository()
        self.problemRepository = ProblemRepository()
        self.service = ProblemService()
    }

    func load(handle: String) async {
        guard case .idle = state else { return }
        state = .loading
        AppLog.debug("RecommendationVM: Loading for \(handle)", category: .ui)

        do {
            // Fetch profile (for rating), catalog, and submission history concurrently.
            async let userFetch       = profileRepository.getProfile(handle: handle)
            async let catalogFetch    = problemRepository.getProblems()
            async let submissionFetch = service.fetchUserSubmissions(handle: handle, count: 1000)

            let user        = try await userFetch
            let catalog     = try await catalogFetch
            let submissions = try await submissionFetch

            // Fall back to 1200 if CF hasn't assigned a rating yet.
            let rating = user.rating ?? 1200

            let recommendations = try RecommendationEngine.shared.recommend(
                problems: catalog,
                userRating: rating,
                submissions: submissions
            )

            state = .loaded(recommendations)
            AppLog.debug("RecommendationVM: Got \(recommendations.count) recommendations", category: .ui)

        } catch {
            let message = (error as? NetworkError)?.errorDescription ?? error.localizedDescription
            AppLog.error("RecommendationVM: \(message)", category: .ui)
            state = .error(message)
        }
    }

    func refresh(handle: String) async {
        state = .idle
        await load(handle: handle)
    }
}
