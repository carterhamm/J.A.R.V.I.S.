//
//  ContinuityView.swift
//  JARVIS
//
//  Enhanced with Google Authentication
//

import SwiftUI
import GoogleSignIn
import FirebaseAuth

struct ContinuityView: View {
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var showError = false
    @State private var gradientPhase: CGFloat = 0
    @Environment(\.colorScheme) var colorScheme
    
    private let gradientTimer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()
            
            // Main content
            VStack(spacing: 40) {
                Spacer()
                
                // J.A.R.V.I.S. Logo and Title
                VStack(spacing: 20) {
                    // Animated logo
                    ZStack {
                        Circle()
                            .fill(Color.clear)
                            .glassEffect(.regular, in: Circle())
                            .frame(width: 150, height: 150)
                            .overlay(
                                Circle()
                                    .stroke(glowGradient, lineWidth: 3)
                                    .blur(radius: 4)
                            )
                        
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 60))
                            .foregroundColor(Color(red: 0, green: 0.6, blue: 0.8))
                            .symbolEffect(.pulse, options: .repeating)
                    }
                    
                    VStack(spacing: 8) {
                        Text("J.A.R.V.I.S.")
                            .font(.system(size: 42, weight: .bold, design: .default))
                            .foregroundColor(.white)
                        
                        Text("Just A Rather Very Intelligent System")
                            .font(.title3)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                
                Spacer()
                
                // Authentication section
                VStack(spacing: 24) {
                    Text("Ready to serve you, sir.")
                        .font(.title2)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    
                    // Continue with Google Button
                    Button(action: signInWithGoogle) {
                        HStack(spacing: 12) {
                            if isLoading {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "globe")
                                    .font(.system(size: 20, weight: .medium))
                            }
                            
                            Text(isLoading ? "Authenticating..." : "Continue with Google")
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 28)
                                .fill(Color.clear)
                                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 28)
                                .stroke(glowGradient, lineWidth: 2)
                                .blur(radius: 2)
                        )
                        .scaleEffect(isLoading ? 0.95 : 1.0)
                        .animation(.easeInOut(duration: 0.1), value: isLoading)
                    }
                    .disabled(isLoading)
                    .padding(.horizontal, 32)
                    
                    // Privacy note
                    Text("Your data is encrypted and secure")
                        .font(.caption)
                        .foregroundColor(.gray.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                
                Spacer()
            }
            .padding()
        }
        .preferredColorScheme(.dark)
        .onReceive(gradientTimer) { _ in
            withAnimation(.linear(duration: 0.2)) {
                gradientPhase = (gradientPhase + 0.05).truncatingRemainder(dividingBy: 1.0)
            }
        }
        .alert("Authentication Error", isPresented: $showError) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            if let errorMessage = errorMessage {
                Text(errorMessage)
            }
        }
    }
    
    private var glowGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: .blue, location: 0.0 + gradientPhase),
                .init(color: Color(red: 0, green: 0.6, blue: 0.8), location: 0.5 + gradientPhase),
                .init(color: .blue, location: 1.0 + gradientPhase)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private func signInWithGoogle() {
        guard !isLoading else { return }
        
        // Light haptic feedback
        HapticManager.shared.impact(style: .light)
        
        isLoading = true
        errorMessage = nil
        
        guard let presentingViewController = UIApplication.shared.windows.first?.rootViewController else {
            handleAuthError("Unable to find view controller")
            return
        }
        
        GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController) { result, error in
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let error = error {
                    self.handleAuthError("Google Sign-In failed: \(error.localizedDescription)")
                    return
                }
                
                guard let user = result?.user,
                      let idToken = user.idToken?.tokenString else {
                    self.handleAuthError("Failed to get authentication token")
                    return
                }
                
                // Create Firebase credential and sign in
                let credential = GoogleAuthProvider.credential(
                    withIDToken: idToken,
                    accessToken: user.accessToken.tokenString
                )
                
                Auth.auth().signIn(with: credential) { authResult, error in
                    DispatchQueue.main.async {
                        if let error = error {
                            self.handleAuthError("Firebase authentication failed: \(error.localizedDescription)")
                        } else {
                            // Success haptic
                            HapticManager.shared.notification(type: .success)
                            // Navigation will be handled automatically by the app's auth state listener
                        }
                    }
                }
            }
        }
    }
    
    private func handleAuthError(_ message: String) {
        print("Auth Error: \(message)")
        errorMessage = message
        showError = true
        
        // Error haptic
        HapticManager.shared.notification(type: .error)
    }
}

#Preview {
    ContinuityView()
}
