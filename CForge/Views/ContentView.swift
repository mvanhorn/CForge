import SwiftUI

extension Color {
    static let darkBackground = Color(red: 0.08, green: 0.08, blue: 0.1)
    static let darkerBackground = Color(red: 0.05, green: 0.05, blue: 0.07)
    static let darkestBackground = Color(red: 0.03, green: 0.03, blue: 0.05)
    static let neonBlue = Color(red: 0.0, green: 0.95, blue: 1.0)
    static let neonPurple = Color(red: 0.3, green: 0.22, blue: 0.98)
    static let neonGreen = Color(red: 0.3, green: 1.0, blue: 0.5)
    static let neonPink = Color(red: 1.0, green: 0.2, blue: 0.7)
    static let textPrimary = Color.white.opacity(0.9)
    static let textSecondary = Color.white.opacity(0.6)
    
        
}

extension UIColor {
    static let darkBackground = UIColor(red: 0.08, green: 0.08, blue: 0.1, alpha: 1.0)
    static let darkerBackground = UIColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1.0)
}

struct ContentView: View {
    var body: some View {
        
        TabView {
                    ContestListView()
                        .tabItem {
                            Label("Contests", systemImage: "calendar")
                        }

                    ProblemListView()
                        .tabItem {
                            Label("Problems", systemImage: "list.bullet")
                        }

                    RecommendedProblemsView()
                        .tabItem {
                            Label("For You", systemImage: "sparkles")
                        }

                    ProfileView()
                        .tabItem {
                            Label("Profile", systemImage: "person.crop.circle")
                        }
                }
                .accentColor(.neonBlue) 
                .preferredColorScheme(.dark)
                .background(Color.clear)
                
    }
}
#Preview {
    ContentView()
}
