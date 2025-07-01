//
//  JARVISApp.swift
//  JARVIS
//
//  Enhanced with Google Authentication
//

import SwiftUI
import UIKit
import SwiftData
import FirebaseCore
import FirebaseAppCheck
import FirebaseAuth
import GoogleSignIn

// MARK: - App Delegate for Google Sign-In
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Configure Firebase
        FirebaseApp.configure()
        
        // Configure AppCheck
        let providerFactory = AppCheckDebugProviderFactory()
        AppCheck.setAppCheckProviderFactory(providerFactory)
        
        // Configure Google Sign-In
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let clientId = plist["CLIENT_ID"] as? String else {
            fatalError("GoogleService-Info.plist not found or CLIENT_ID missing")
        }
        
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientId)
        
        return true
    }
    
    func application(_ app: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        return GIDSignIn.sharedInstance.handle(url)
    }
}

// MARK: - Auth State Manager
class AuthStateManager: ObservableObject {
    @Published var isSignedIn = false
    @Published var isLoading = true
    
    private var authListenerHandle: AuthStateDidChangeListenerHandle?
    
    init() {
        setupAuthListener()
    }
    
    deinit {
        if let handle = authListenerHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }
    
    private func setupAuthListener() {
        authListenerHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                self?.isSignedIn = user != nil
                self?.isLoading = false
            }
        }
    }
}

@main
struct JARVISApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authStateManager = AuthStateManager()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            Group {
                if authStateManager.isLoading {
                    // Loading screen
                    ZStack {
                        Color.black.ignoresSafeArea()
                        
                        VStack(spacing: 20) {
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 60))
                                .foregroundColor(Color(red: 0, green: 0.6, blue: 0.8))
                                .symbolEffect(.pulse, options: .repeating)
                            
                            Text("J.A.R.V.I.S.")
                                .font(.title.bold())
                                .foregroundColor(.white)
                            
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 0, green: 0.6, blue: 0.8)))
                                .scaleEffect(1.2)
                        }
                    }
                    .preferredColorScheme(.dark)
                } else if authStateManager.isSignedIn {
                    AlternateTestView()
                        .environmentObject(ThemeManager.shared)
                        .environmentObject(JARVISSettings.shared)
                } else {
                    ContinuityView()
                }
            }
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
        }
        .modelContainer(sharedModelContainer)
    }
}

// MARK: - Updated Main View with Theme Support
struct ThemedAlternateTestView: View {
    @State private var showMessages = false
    @State private var showRadialMenu = true
    @StateObject private var jarvis = JARVISViewModel()
    @EnvironmentObject var themeManager: ThemeManager

    private var mainContent: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            AlternateParticleSphereView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .overlay {
                    if showMessages {
                        JARVISChatView()
                            .environmentObject(themeManager)
                            .transition(.opacity)
                            .onAppear {
                                showRadialMenu = false
                            }
                            .onDisappear {
                                showRadialMenu = true
                            }
                    }
                }
                .overlay {
                    if jarvis.showImages && !jarvis.currentImages.isEmpty {
                        ImageView(imageURLs: jarvis.currentImages)
                            .transition(.opacity)
                            .onTapGesture {
                                jarvis.showImages = false
                            }
                            .onAppear {
                                showRadialMenu = false
                            }
                            .onDisappear {
                                showRadialMenu = true
                            }
                    }
                }

            VStack {
                Spacer()
                
                if let query = jarvis.lastUserQuery, !showMessages, !jarvis.showImages {
                    Text("You said: \"\(query)\"")
                        .foregroundColor(themeManager.currentTheme.primaryColor.opacity(0.45))
                        .padding(.bottom, 50)
                }
            }
            
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    RadialMenuButton(isVisible: $showRadialMenu)
                        .environmentObject(themeManager)
                        .padding(.trailing, 20)
                        .padding(.bottom, 50)
                }
            }

            if jarvis.isOffline {
                RoundedRectangle(cornerRadius: UIScreen.main.displayCornerRadius, style: .continuous)
                    .fill(Color.clear)
                    .innerGlow(color: Color.red.opacity(0.8), lineWidth: 12, blurRadius: 5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showMessages)) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                showMessages.toggle()
                showRadialMenu = !showMessages
            }
            HapticManager.shared.impact(style: .medium)
        }
    }

    var body: some View {
        NavigationView {
            mainContent
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
