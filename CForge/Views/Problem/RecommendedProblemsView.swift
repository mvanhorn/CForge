import SwiftUI

struct RecommendedProblemsView: View {

    @StateObject private var viewModel = RecommendationViewModel()
    @EnvironmentObject var userManager: UserManager

    var body: some View {
        NavigationStack {
            ZStack {
                background

                switch viewModel.state {
                case .idle, .loading:
                    loadingView

                case .error(let message):
                    errorView(message)

                case .loaded(let results):
                    if results.isEmpty {
                        emptyView
                    } else {
                        resultsList(results)
                    }
                }
            }
            .navigationTitle("For You")
            .navigationDestination(for: Problem.self) { problem in
                ProblemListView.ProblemDetailView(problem: problem)
                    .id(problem.id)
            }
            .task { await viewModel.load(handle: userManager.userHandle) }
        }
    }

    // MARK: - Sub-views

    private var background: some View {
        LinearGradient(
            colors: [.darkBackground, .darkestBackground],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.neonBlue)
            Text("Analyzing your history...")
                .font(.subheadline)
                .foregroundColor(.textSecondary)
        }
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 50))
                .foregroundStyle(
                    LinearGradient(colors: [.neonBlue, .neonPurple], startPoint: .top, endPoint: .bottom)
                )
            Text("No recommendations yet")
                .font(.headline)
                .foregroundColor(.textPrimary)
            Text("Solve a few problems first so the model can learn your strengths.")
                .font(.subheadline)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundColor(.textSecondary)
            Text(message)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Retry") {
                Task { await viewModel.refresh(handle: userManager.userHandle) }
            }
            .buttonStyle(.bordered)
        }
    }

    private func resultsList(_ results: [ScoredProblem]) -> some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(results) { scored in
                    RecommendedProblemRow(scored: scored)
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .refreshable {
            await viewModel.refresh(handle: userManager.userHandle)
        }
    }
}

// MARK: - Row

private struct RecommendedProblemRow: View {

    let scored: ScoredProblem

    var body: some View {
        NavigationLink(value: scored.problem) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(scored.problem.title)
                        .font(.headline)
                        .foregroundColor(.textPrimary)

                    Spacer()

                    matchBadge
                }

                if let rating = scored.problem.rating {
                    HStack(spacing: 4) {
                        Text("Rating:")
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)
                        Text("\(rating)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.neonBlue, .neonPurple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        Spacer()
                        Text("#\(scored.problem.contestId)\(scored.problem.index)")
                            .font(.system(size: 12, weight: .bold))
                            .padding(6)
                            .background(
                                LinearGradient(
                                    colors: [.neonBlue.opacity(0.2), .neonPurple.opacity(0.2)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(6)
                    }
                }

                if !scored.problem.tags.isEmpty {
                    tagsView
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.darkerBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                LinearGradient(
                                    colors: [.neonBlue.opacity(0.4), .neonPurple.opacity(0.4)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var matchBadge: some View {
        let pct = Int(scored.score * 100)
        return Text("\(pct)% match")
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                LinearGradient(
                    colors: [.neonBlue.opacity(0.25), .neonPurple.opacity(0.25)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundColor(.neonBlue)
            .cornerRadius(8)
    }

    private var tagsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(scored.problem.tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            LinearGradient(
                                colors: [.neonBlue.opacity(0.2), .neonPurple.opacity(0.2)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.neonBlue)
                        .cornerRadius(8)
                }
            }
        }
    }
}

#Preview {
    RecommendedProblemsView()
        .environmentObject(UserManager(userHandle: "tourist"))
}
