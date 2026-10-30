import SwiftUI
import SDWebImageSwiftUI
import Charts

struct ProfileView: View {

    @StateObject private var viewModel = ProfileViewModel()
    @EnvironmentObject var userManager: UserManager
    @State private var showLogoutConfirm = false
    @AppStorage("userHandle") private var storedHandle: String?

    private var userHandle: String { userManager.userHandle }

    // MARK: - Body

    var body: some View {
        ScrollView {
            switch viewModel.state {
            case .idle, .loading:
                ProgressView("Fetching Profile...")
                    .frame(maxWidth: .infinity, minHeight: 400)
            case .loaded(let snapshot):
                VStack(spacing: 20) {
                    profileHeader(user: snapshot.user)
                    ratingSection(user: snapshot.user)
                    statsSection(user: snapshot.user, solvedCount: snapshot.solvedCount)
                    ratingChart(history: snapshot.ratingHistory)
                }
                .padding()
            case .error(let message):
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "Couldn't Load Profile",
                    subtitle: message,
                    action: .init(label: "Retry") {
                        Task { await viewModel.retry(handle: userHandle) }
                    }
                )
                .frame(minHeight: 400)
            }
        }
        .navigationTitle("Profile")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if viewModel.connectionState != .disconnected {
                    ConnectionStatusPill(state: viewModel.connectionState)
                }
            }
        }
        .background(
            LinearGradient(
                colors: [.darkBackground, .darkestBackground],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .task { await viewModel.loadProfile(handle: userHandle) }
        .verdictToast(verdict: $viewModel.incomingVerdict) { viewModel.dismissVerdict() }
        .overlay(alignment: .top) {
            if viewModel.isDataStale, let date = viewModel.dataLastUpdated {
                StalenessBanner(lastUpdated: date)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .animation(.easeInOut, value: viewModel.isDataStale)
            }
        }
    }

    // MARK: - Profile Header

    private func profileHeader(user: CodeforcesUser) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [.darkerBackground, .darkBackground],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 80, height: 80)

                WebImage(url: normalizeAvatarURL(user.titlePhoto ?? user.avatar)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Image(systemName: "person.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.neonBlue, .neonPurple],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .indicator(.activity)
                .frame(width: 80, height: 80)
                .clipShape(Circle())
            }
            .overlay(
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [.neonBlue, .neonPurple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
            )
            .shadow(color: .neonBlue.opacity(0.4), radius: 8)

            VStack(alignment: .leading, spacing: 4) {
                Text(user.handle)
                    .font(.title.bold())
                Text(user.rank ?? "Unranked")
                    .font(.headline)
                    .foregroundColor(rankColor(for: user.rank ?? ""))
            }

            Spacer()

            Button(action: { showLogoutConfirm = true }) {
                Image(systemName: "power")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.red)
                    .padding(10)
                    .background(Circle().fill(Color.red.opacity(0.2)))
            }
            .confirmationDialog("Logout", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
                Button("Log Out", role: .destructive) {
                    storedHandle = nil
                    userManager.userHandle = ""
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to log out?")
            }
        }
        .padding(.vertical)
    }

    // MARK: - Rating Section

    private func ratingSection(user: CodeforcesUser) -> some View {
        let currentRating = viewModel.liveRating ?? user.rating ?? 0
        let maxRatingValue = user.maxRating ?? 1
        let progressPercentage = Int((Double(currentRating) / Double(maxRatingValue)) * 100)

        return VStack(spacing: 12) {
            HStack {
                Text("Rating:")
                    .font(.headline)
                    .foregroundColor(.textSecondary)
                Spacer()
                Text("\(currentRating)")
                    .font(.system(.title3).weight(.bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.neonBlue, .neonPurple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .contentTransition(.numericText())
            }
            .frame(height: 20)

            ProgressView(value: Double(currentRating), total: Double(maxRatingValue))
                .progressViewStyle(NeonProgressStyle())
                .overlay(
                    HStack {
                        Text("\(currentRating)/\(maxRatingValue)")
                            .font(.caption)
                        Spacer()
                        Text("\(progressPercentage)%")
                            .font(.caption)
                    }
                    .foregroundColor(.textSecondary)
                    .padding(.horizontal, 4)
                    .offset(y: 14)
                )
                .frame(height: 20)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.darkerBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [.neonBlue.opacity(0.4), .neonPurple.opacity(0.4)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .cornerRadius(12)
    }

    // MARK: - Stats Section

    private func statsSection(user: CodeforcesUser, solvedCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("User Statistics")
                .font(.headline)
                .foregroundColor(.textSecondary)

            HStack(spacing: 10) {
                StatCard(value: "\(solvedCount)", label: "Solved")
                StatCard(value: "\(user.contribution ?? 0)", label: "Contributions")
                StatCard(value: "\(user.rating ?? 0)", label: "Rating")
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
                                gradient: Gradient(colors: [.neonBlue.opacity(0.4), .neonPurple.opacity(0.4)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .cornerRadius(12)
    }

    // MARK: - Rating Chart

    private func ratingChart(history: [RatingChange]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rating Progress")
                .font(.headline)
                .foregroundColor(.textSecondary)

            if history.isEmpty {
                ProgressView()
                    .frame(height: 150)
            } else {
                Chart {
                    ForEach(history, id: \.contestId) { change in
                        LineMark(
                            x: .value("Date", Date(timeIntervalSince1970: Double(change.ratingUpdateTimeSeconds))),
                            y: .value("Rating", change.newRating)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.neonBlue, .neonPurple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { _ in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.month(.abbreviated))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 200)
                .padding(.vertical, 8)
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
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }

    // MARK: - Helpers

    private func rankColor(for rank: String) -> Color {
        switch rank.lowercased() {
        case let r where r.contains("legendary grandmaster"): return .red
        case let r where r.contains("grandmaster"):           return .red
        case let r where r.contains("international master"):  return .orange
        case let r where r.contains("master"):                return .orange
        case let r where r.contains("candidate master"):      return .purple
        case let r where r.contains("expert"):                return .blue
        case let r where r.contains("specialist"):            return .cyan
        case let r where r.contains("pupil"):                 return .green
        default:                                               return .gray
        }
    }

    // MARK: - Nested Views

    struct NeonProgressStyle: ProgressViewStyle {
        func makeBody(configuration: Configuration) -> some View {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .frame(height: 8)
                    .foregroundColor(.darkerBackground)

                RoundedRectangle(cornerRadius: 4)
                    .frame(
                        width: configuration.fractionCompleted.map {
                            CGFloat($0) * UIScreen.main.bounds.width - 32
                        },
                        height: 8
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.neonBlue, .neonPurple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
        }
    }

    struct StatCard: View {
        let value: String
        let label: String

        var body: some View {
            VStack {
                Text(value)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.neonBlue, .neonPurple],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.darkerBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [.neonBlue.opacity(0.4), .neonPurple.opacity(0.4)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .cornerRadius(12)
        }
    }
}

// MARK: - Preview
#Preview {
    NavigationStack {
        ProfileView()
    }
    .environmentObject(UserManager(userHandle: "tourist"))
}
