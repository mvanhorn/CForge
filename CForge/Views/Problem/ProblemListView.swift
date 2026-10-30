import SwiftUI
import WebKit

struct ProblemListView: View {
  
    @StateObject private var viewModel = ProblemListViewModel()
    @State private var searchText = ""
    @State private var selectedTag: String?
    @State private var selectedRatingRange: RatingRange?

    

    var body: some View {
        NavigationStack {
            ZStack {
                switch viewModel.state {
                case .loading:
                    VStack {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.neonBlue)
                        Text("Loading Problems...")
                            .font(.headline)
                            .foregroundColor(.textSecondary)
                            .padding(.top)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                case .error(let message):
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 50))
                            .foregroundColor(.red)
                        Text(message)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.textPrimary)
                            .padding()
                        Button("Retry") {
                            Task { await viewModel.loadProblems(forceRefresh: true) }
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                case .idle, .loaded:
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            SearchBar(text: $searchText, placeholder: "Search by name or rating")
                                .padding(.horizontal)

                            Text("Tags")
                                .font(.caption2)
                                .foregroundColor(.textSecondary)
                                .padding(.horizontal)
                            tagFilterBar
                                .padding(.bottom, 8)

                            Text("Rating")
                                .font(.caption2)
                                .foregroundColor(.textSecondary)
                                .padding(.horizontal)
                            ratingFilterBar
                                .padding(.bottom, 8)

                            ForEach(viewModel.filteredProblems) { problem in
                                ProblemRow(problem: problem)
                            }
                            .padding(.horizontal)
                        }
                        .padding(.vertical)
                    }
                    .refreshable {
                        await viewModel.loadProblems(forceRefresh: true)
                    }
                }
            }
            .navigationTitle("Problems")
            .navigationDestination(for: Problem.self) { problem in
                ProblemDetailView(problem: problem)
                    .id(problem.id)
            }

            .background(
                LinearGradient(
                    colors: [.darkBackground, .darkestBackground],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .task { await viewModel.loadProblems() }
            .task(id: searchText) {
                do {
                    try await Task.sleep(nanoseconds: 300_000_000)
                    viewModel.filterProblems(query: searchText, tag: selectedTag, ratingRange: selectedRatingRange)
                } catch {}
            }
            .task(id: selectedTag) {
                viewModel.filterProblems(query: searchText, tag: selectedTag, ratingRange: selectedRatingRange)
            }
            .task(id: selectedRatingRange) {
                viewModel.filterProblems(query: searchText, tag: selectedTag, ratingRange: selectedRatingRange)
            }
        }
    }


        // MARK: - Detail View Tabs
        struct DescriptionTab: View {
            let problem: Problem
            
            var body: some View {
                WebView(url: URL(string: "https://codeforces.com/contest/\(problem.contestId)/problem/\(problem.index)")!)
            }
        }
        
        struct WebView: UIViewRepresentable {
            let url: URL
            
            func makeUIView(context: Context) -> WKWebView {
                let config = WKWebViewConfiguration()
                let userContentController = WKUserContentController()
                
                let userScript = CodeforcesContentSanitizer.injectionScript()
                userContentController.addUserScript(userScript)
                config.userContentController = userContentController
                
                return WKWebView(frame: .zero, configuration: config)
            }
            
            func updateUIView(_ uiView: WKWebView, context: Context) {
                let request = URLRequest(url: url)
                uiView.load(request)
            }
        }
    
    private var tagFilterBar: some View {
        let problems: [Problem]
        if case .loaded(let p) = viewModel.state {
            problems = p
        } else {
            problems = []
        }
        
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(Set(problems.flatMap { $0.tags })).sorted(), id: \.self) { tag in
                    Button(action: {
                        selectedTag = selectedTag == tag ? nil : tag
                    }) {
                        Text(tag.capitalized)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                ZStack {
                                    if selectedTag == tag {
                                        LinearGradient(
                                            colors: [.neonBlue, .neonPurple],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    } else {
                                        Color.darkerBackground
                                    }
                                }
                            )
                            .foregroundColor(selectedTag == tag ? .white : .primary)
                            .cornerRadius(12)
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
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }
    
    private var ratingFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(RatingRange.allCases) { ratingRange in
                    Button(action: {
                        selectedRatingRange = selectedRatingRange == ratingRange ? nil : ratingRange
                    }) {
                        Text(ratingRange.label)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                ZStack {
                                    if selectedRatingRange == ratingRange {
                                        LinearGradient(
                                            colors: [.neonBlue, .neonPurple],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    } else {
                                        Color.darkerBackground
                                    }
                                }
                            )
                            .foregroundColor(selectedRatingRange == ratingRange ? .white : .primary)
                            .cornerRadius(12)
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
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Problem Row
    struct ProblemRow: View {
        let problem: Problem
        
        var body: some View {
            NavigationLink(value: problem) {
                VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(problem.title)
                                    .font(.headline)
                                    .foregroundColor(.textPrimary)
                                
                                Spacer()
                                
                                Text("#\(problem.contestId)\(problem.index)")
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
                            
                            if let rating = problem.rating {
                                HStack {
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
                                }
                            }
                            
                            if !problem.tags.isEmpty {
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
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
        
        
        private var tagsView: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(problem.tags, id: \.self) { tag in
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
}

extension ProblemListView {
    struct ProblemDetailView: View {
        let problem: Problem
        @State private var selectedTab = 0
        
        var body: some View {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        Text(problem.title)
                            .font(.title2.bold())
                            .foregroundColor(.textPrimary)
                        
                        Spacer()
                        
                        Text("#\(problem.contestId)\(problem.index)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.neonBlue)
                            .padding(8)
                            .background(
                                LinearGradient( 
                                    colors: [.neonBlue.opacity(0.2), .neonPurple.opacity(0.2)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(8)
                    }
                    
                    if let rating = problem.rating {
                        HStack(spacing: 4) {
                            Text("Rating:")
                                .font(.subheadline)
                                .foregroundColor(.textSecondary)
                            
                            Text("\(rating)")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.neonBlue, .neonPurple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        }
                    }
                    
                    if !problem.tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(problem.tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.caption)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            LinearGradient(
                                                colors: [.neonBlue.opacity(0.2), .neonPurple.opacity(0.2)],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .foregroundColor(.neonBlue)
                                        .cornerRadius(12)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top)
                
                Picker("", selection: $selectedTab) {
                    Text("Description").tag(0)
                    Text("Submit").tag(1)
                    Text("Submissions").tag(2)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.darkBackground)
                
                TabView(selection: $selectedTab) {
                    DescriptionTab(problem: problem)
                        .tag(0)
                    
                    SubmitLauncherView(problem: problem)
                        .tag(1)
                    
                    ProblemSubmissionsView(problem: problem)
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle("Problem")
            .navigationBarTitleDisplayMode(.inline)
            .background(
                LinearGradient(
                    colors: [.darkBackground, .darkerBackground],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
        }
        

        
    }
}

struct SearchBar: View {
    @Binding var text: String
    let placeholder: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                            .foregroundColor(.neonBlue)
                            .padding(.leading, 12)

                        TextField(placeholder, text: $text)
                            .foregroundColor(.textPrimary)
                            .autocapitalization(.none)
                            .textInputAutocapitalization(.never)

                        if !text.isEmpty {
                            Button(action: { text = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.neonPurple)
                            }
                            .padding(.trailing, 12)
                        }
        }
        .padding(.vertical, 10)
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
         .padding(.horizontal, 4)
    }
}


// MARK: - Preview
#Preview {
    ProblemListView()
}
