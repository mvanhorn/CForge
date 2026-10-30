import SwiftUI
import SwiftData

@main

struct CForgeApp: App {
    @State private var showSplash = true
    @AppStorage("userHandle") private var userHandle: String?
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                AnimatedGradientBackground(
                    colors: [.darkBackground, .darkerBackground, .darkestBackground],
                    speed: 8
                )
                
                if showSplash {
                    SplashView(onComplete: {})
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation {
                                    showSplash = false
                                }
                            }
                        }
                } else {
                    if let handle = userHandle {
                        ContentView()
                            .environmentObject(UserManager(userHandle: handle))
                    } else {
                        LoginView()
                    }
                }
            }
        }
        .modelContainer(PersistenceController.shared.container)
    }
}

class UserManager: ObservableObject {
    @Published var userHandle: String
    
    init(userHandle: String) {
        self.userHandle = userHandle
    }
}

struct LoginView: View {
    @AppStorage("userHandle") private var storedHandle: String?
    @State private var inputHandle = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        
            VStack(spacing: 24) {
                // App Logo
                Image(systemName: "bolt.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.neonBlue, .neonPurple],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .padding(.bottom, 20)
                
                VStack(spacing: 8) {
                    Text("Welcome")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(.textPrimary)
                    
                    Text("Please sign in to continue and get the new experience of Codeforces")
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                
                VStack(spacing: 20) {
                    TextField("Enter your CODEFORCES username", text: $inputHandle)
                        .textFieldStyle(NeonTextFieldStyle())
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .overlay(
                            HStack {
                                Image(systemName: "person.fill")
                                    .foregroundColor(.neonBlue)
                                    .padding(.leading, 16)
                                Spacer()
                            }
                        )
                    
                    if isLoading {
                        ProgressView()
                            .tint(.neonPurple)
                    } else {
                        Button(action: verifyHandle) {
                            Text("Continue")
                                .font(.headline.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 30)
                        }
                        .buttonStyle(NeonButtonStyle())
                        .cornerRadius(50)
                    }
                }
                .padding(.horizontal, 24)
                
                Spacer()
                
                
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Text("Don't have an account?")
                            .foregroundColor(.textSecondary)
                        
                        Button("Sign Up") {
                            if let url = URL(string: "https://codeforces.com/register") {
                                UIApplication.shared.open(url)
                            }
                        }
                        .foregroundColor(.neonBlue)
                    }
                    .font(.caption)
                    
                    Text("Made with ♥ by Sandesh")
                        .font(.caption2)
                        .foregroundColor(.textSecondary)
                        .padding(.top, 8)
                }
            }
            .padding(.vertical, 40)
            .background(
                LinearGradient(
                    colors: [.darkestBackground, .darkerBackground],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            
        
        }
    
    private func verifyHandle() {
        guard !inputHandle.isEmpty else {
            errorMessage = "Please enter a handle"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        let apiUrl = "https://codeforces.com/api/user.info?handles=\(inputHandle)"
        
        URLSession.shared.dataTask(with: URL(string: apiUrl)!) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false
                
                if let error = error {
                    errorMessage = "Network error: \(error.localizedDescription)"
                    return
                }
                
                guard let data = data else {
                    errorMessage = "No data received"
                    return
                }
                
                do {
                    let response = try JSONDecoder().decode(CodeforcesProfileResponse.self, from: data)
                    if response.status == "OK" && !response.result.isEmpty {
                        storedHandle = inputHandle
                    } else {
                        errorMessage = "Invalid Codeforces handle"
                    }
                } catch {
                    errorMessage = "Invalid response format"
                }
            }
        }.resume()
    }
}

struct NeonTextFieldStyle: TextFieldStyle {
        func _body(configuration: TextField<Self._Label>) -> some View {
            configuration
                .padding(.leading, 36)
                .padding(.vertical, 14)
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
                .foregroundColor(.textPrimary)
        }
    }

struct NeonButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
                configuration.label
                    .padding()
                    .foregroundColor(.white)
                    .background(
                        LinearGradient(
                            colors: [.neonBlue, .neonPurple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .cornerRadius(12)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.white.opacity(0.2), lineWidth: 1)
                    )
                    .scaleEffect(configuration.isPressed ? 0.96 : 1)
                    .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
            }
}

#Preview {
    NavigationStack {
        LoginView()
    }
}

