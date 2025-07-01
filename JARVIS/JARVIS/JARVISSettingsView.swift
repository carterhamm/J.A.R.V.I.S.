//
//  JARVISSettingsView.swift
//  JARVIS
//
//  Enhanced settings panel with working functionality and theme support
//

import SwiftUI
import AVFoundation
import Speech
import EventKit
import MediaPlayer
import UserNotifications
import FirebaseAuth
import Foundation
import FirebaseFunctions
import UIKit

// MARK: - Theme Management
class ThemeManager: ObservableObject {
    @Published var currentTheme: JARVISTheme = .classicBlue
    
    static let shared = ThemeManager()
    
    private init() {
        loadTheme()
    }
    
    func setTheme(_ theme: JARVISTheme) {
        currentTheme = theme
        saveTheme()
    }
    
    private func saveTheme() {
        UserDefaults.standard.set(currentTheme.rawValue, forKey: "jarvis_theme")
    }
    
    private func loadTheme() {
        if let savedTheme = UserDefaults.standard.string(forKey: "jarvis_theme"),
           let theme = JARVISTheme(rawValue: savedTheme) {
            currentTheme = theme
        }
    }
}

enum JARVISTheme: String, CaseIterable {
    case classicBlue = "Classic Blue"
    case ironRed = "Iron Red"
    case arcReactor = "Arc Reactor"
    case stealthBlack = "Stealth Black"
    case hologramGreen = "Hologram Green"
    
    var primaryColor: Color {
        switch self {
        case .classicBlue:
            return Color(red: 0, green: 0.6, blue: 0.8)
        case .ironRed:
            return Color(red: 0.8, green: 0.2, blue: 0.2)
        case .arcReactor:
            return Color(red: 0.3, green: 0.8, blue: 1.0)
        case .stealthBlack:
            return Color(red: 0.3, green: 0.3, blue: 0.3)
        case .hologramGreen:
            return Color(red: 0.2, green: 0.8, blue: 0.4)
        }
    }
    
    var secondaryColor: Color {
        return primaryColor.opacity(0.7)
    }
}

// MARK: - Settings Storage
class JARVISSettings: ObservableObject {
    @Published var voiceActivationEnabled: Bool {
        didSet { UserDefaults.standard.set(voiceActivationEnabled, forKey: "voice_activation") }
    }
    @Published var hotwordSensitivity: Float {
        didSet { UserDefaults.standard.set(hotwordSensitivity, forKey: "hotword_sensitivity") }
    }
    @Published var voiceVolume: Float {
        didSet { UserDefaults.standard.set(voiceVolume, forKey: "voice_volume") }
    }
    @Published var speechRate: Float {
        didSet { UserDefaults.standard.set(speechRate, forKey: "speech_rate") }
    }
    @Published var useElevenLabsVoice: Bool {
        didSet { UserDefaults.standard.set(useElevenLabsVoice, forKey: "use_elevenlabs") }
    }
    @Published var selectedVoice: String {
        didSet { UserDefaults.standard.set(selectedVoice, forKey: "selected_voice") }
    }
    @Published var enableHapticFeedback: Bool {
        didSet { UserDefaults.standard.set(enableHapticFeedback, forKey: "haptic_feedback") }
    }
    @Published var autoLocationUpdates: Bool {
        didSet { UserDefaults.standard.set(autoLocationUpdates, forKey: "auto_location") }
    }
    @Published var enableNotifications: Bool {
        didSet { UserDefaults.standard.set(enableNotifications, forKey: "notifications_enabled") }
    }
    @Published var darkModeOnly: Bool {
        didSet { UserDefaults.standard.set(darkModeOnly, forKey: "dark_mode_only") }
    }
    @Published var particleDensity: Float {
        didSet { UserDefaults.standard.set(particleDensity, forKey: "particle_density") }
    }
    @Published var glowIntensity: Float {
        didSet { UserDefaults.standard.set(glowIntensity, forKey: "glow_intensity") }
    }
    @Published var conversationTimeout: Float {
        didSet { UserDefaults.standard.set(conversationTimeout, forKey: "conversation_timeout") }
    }
    @Published var clearDataOnExit: Bool {
        didSet { UserDefaults.standard.set(clearDataOnExit, forKey: "clear_data_exit") }
    }
    @Published var enableAnalytics: Bool {
        didSet { UserDefaults.standard.set(enableAnalytics, forKey: "analytics_enabled") }
    }
    @Published var offlineMode: Bool {
        didSet { UserDefaults.standard.set(offlineMode, forKey: "offline_mode") }
    }
    @Published var enableDebugMode: Bool {
        didSet { UserDefaults.standard.set(enableDebugMode, forKey: "debug_mode") }
    }
    @Published var autoBackupConversations: Bool {
        didSet { UserDefaults.standard.set(autoBackupConversations, forKey: "auto_backup") }
    }
    @Published var voiceGender: String {
        didSet { UserDefaults.standard.set(voiceGender, forKey: "voice_gender") }
    }
    
    static let shared = JARVISSettings()
    
    private init() {
        self.voiceActivationEnabled = UserDefaults.standard.object(forKey: "voice_activation") as? Bool ?? true
        self.hotwordSensitivity = UserDefaults.standard.object(forKey: "hotword_sensitivity") as? Float ?? 0.7
        self.voiceVolume = UserDefaults.standard.object(forKey: "voice_volume") as? Float ?? 0.8
        self.speechRate = UserDefaults.standard.object(forKey: "speech_rate") as? Float ?? 0.52
        self.useElevenLabsVoice = UserDefaults.standard.object(forKey: "use_elevenlabs") as? Bool ?? true
        self.selectedVoice = UserDefaults.standard.string(forKey: "selected_voice") ?? "Rachel"
        self.enableHapticFeedback = UserDefaults.standard.object(forKey: "haptic_feedback") as? Bool ?? true
        self.autoLocationUpdates = UserDefaults.standard.object(forKey: "auto_location") as? Bool ?? true
        self.enableNotifications = UserDefaults.standard.object(forKey: "notifications_enabled") as? Bool ?? true
        self.darkModeOnly = UserDefaults.standard.object(forKey: "dark_mode_only") as? Bool ?? true
        self.particleDensity = UserDefaults.standard.object(forKey: "particle_density") as? Float ?? 1.0
        self.glowIntensity = UserDefaults.standard.object(forKey: "glow_intensity") as? Float ?? 0.8
        self.conversationTimeout = UserDefaults.standard.object(forKey: "conversation_timeout") as? Float ?? 5.0
        self.clearDataOnExit = UserDefaults.standard.object(forKey: "clear_data_exit") as? Bool ?? false
        self.enableAnalytics = UserDefaults.standard.object(forKey: "analytics_enabled") as? Bool ?? false
        self.offlineMode = UserDefaults.standard.object(forKey: "offline_mode") as? Bool ?? false
        self.enableDebugMode = UserDefaults.standard.object(forKey: "debug_mode") as? Bool ?? false
        self.autoBackupConversations = UserDefaults.standard.object(forKey: "auto_backup") as? Bool ?? true
        self.voiceGender = UserDefaults.standard.string(forKey: "voice_gender") ?? "British Male"
    }
}

struct JARVISSettingsView: View {
    @StateObject private var settings = JARVISSettings.shared
    @StateObject private var themeManager = ThemeManager.shared
    @State private var showAdvancedSettings = false
    @State private var showingResetAlert = false
    @State private var showingPermissionsSheet = false
    @State private var showingSignOutAlert = false
    
    private let elevenLabsVoices = ["Rachel", "Drew", "Clyde", "Paul", "Domi", "Dave", "Fin", "Sarah", "Antoni"]
    private let voiceGenderOptions = ["British Male", "British Female", "American Male", "American Female"]
    
    var currentUser: String {
        Auth.auth().currentUser?.email ?? "Unknown User"
    }
    
    var body: some View {
        ZStack {
            // Background with Liquid Glass effect
            Color.black.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Header Section
                    headerSection
                    
                    // Account Section
                    accountSection
                    
                    // Voice & Audio Settings
                    voiceAudioSection
                    
                    // Interface & Appearance
                    interfaceSection
                    
                    // Permissions & Privacy
                    permissionsSection
                    
                    // Advanced Settings
                    advancedSection
                    
                    // About & Support
                    aboutSection
                    
                    Spacer(minLength: 50)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .alert("Reset All Settings", isPresented: $showingResetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                resetAllSettings()
            }
        } message: {
            Text("This will reset all J.A.R.V.I.S. settings to their defaults. This action cannot be undone.")
        }
        .alert("Sign Out", isPresented: $showingSignOutAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                signOut()
            }
        } message: {
            Text("Are you sure you want to sign out of J.A.R.V.I.S.?")
        }
        .sheet(isPresented: $showingPermissionsSheet) {
            PermissionsHelpView()
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 15) {
            // J.A.R.V.I.S. Logo/Avatar
            ZStack {
                Circle()
                    .fill(Color.clear)
                    .glassEffect()
                    .frame(width: 120, height: 120)
                
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 50))
                    .foregroundColor(themeManager.currentTheme.primaryColor)
                    .symbolEffect(.pulse, options: .repeating)
            }
            
            Text("J.A.R.V.I.S.")
                .font(.title.bold())
                .foregroundColor(.white)
            
            Text("Just A Rather Very Intelligent System")
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 10)
    }
    
    private var accountSection: some View {
        SettingsSection(
            title: "Account",
            icon: "person.circle",
            themeColor: themeManager.currentTheme.primaryColor
        ) {
            VStack(spacing: 15) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Signed in as")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text(currentUser)
                            .foregroundColor(.white)
                            .fontWeight(.medium)
                    }
                    Spacer()
                }
                
                SettingsButton(
                    title: "Sign Out",
                    subtitle: "Switch to a different account",
                    themeColor: themeManager.currentTheme.primaryColor,
                    action: { showingSignOutAlert = true }
                )
            }
        }
    }
    
    private var voiceAudioSection: some View {
        SettingsSection(
            title: "Voice & Audio",
            icon: "speaker.wave.3",
            themeColor: themeManager.currentTheme.primaryColor
        ) {
            VStack(spacing: 15) {
                SettingsToggle(
                    title: "Voice Activation",
                    subtitle: "Respond to 'Hey J.A.R.V.I.S.'",
                    isOn: $settings.voiceActivationEnabled,
                    themeColor: themeManager.currentTheme.primaryColor
                )
                
                if settings.voiceActivationEnabled {
                    SettingsSlider(
                        title: "Hotword Sensitivity",
                        value: $settings.hotwordSensitivity,
                        range: 0.1...1.0,
                        subtitle: settings.hotwordSensitivity > 0.8 ? "Very Sensitive" : settings.hotwordSensitivity > 0.5 ? "Balanced" : "Conservative",
                        themeColor: themeManager.currentTheme.primaryColor
                    )
                    
                    SettingsSlider(
                        title: "Conversation Timeout",
                        value: $settings.conversationTimeout,
                        range: 2.0...10.0,
                        subtitle: "\(Int(settings.conversationTimeout)) seconds",
                        themeColor: themeManager.currentTheme.primaryColor
                    )
                }
                
                SettingsToggle(
                    title: "ElevenLabs Voice",
                    subtitle: "Use premium AI voice synthesis",
                    isOn: $settings.useElevenLabsVoice,
                    themeColor: themeManager.currentTheme.primaryColor
                )
                
                if settings.useElevenLabsVoice {
                    SettingsPicker(
                        title: "Voice Character",
                        selection: $settings.selectedVoice,
                        options: elevenLabsVoices,
                        themeColor: themeManager.currentTheme.primaryColor
                    )
                } else {
                    SettingsPicker(
                        title: "System Voice",
                        selection: $settings.voiceGender,
                        options: voiceGenderOptions,
                        themeColor: themeManager.currentTheme.primaryColor
                    )
                }
                
                SettingsSlider(
                    title: "Speech Rate",
                    value: $settings.speechRate,
                    range: 0.3...0.8,
                    subtitle: settings.speechRate > 0.6 ? "Fast" : settings.speechRate > 0.5 ? "Normal" : "Slow",
                    themeColor: themeManager.currentTheme.primaryColor
                )
                
                SettingsSlider(
                    title: "Volume",
                    value: $settings.voiceVolume,
                    range: 0.0...1.0,
                    subtitle: "\(Int(settings.voiceVolume * 100))%",
                    themeColor: themeManager.currentTheme.primaryColor
                )
            }
        }
    }
    
    private var interfaceSection: some View {
        SettingsSection(
            title: "Interface & Appearance",
            icon: "paintbrush",
            themeColor: themeManager.currentTheme.primaryColor
        ) {
            VStack(spacing: 15) {
                SettingsPicker(
                    title: "Color Theme",
                    selection: Binding(
                        get: { themeManager.currentTheme.rawValue },
                        set: { newValue in
                            if let theme = JARVISTheme(rawValue: newValue) {
                                themeManager.setTheme(theme)
                                HapticManager.shared.impact(style: .light)
                            }
                        }
                    ),
                    options: JARVISTheme.allCases.map { $0.rawValue },
                    themeColor: themeManager.currentTheme.primaryColor
                )
                
                SettingsSlider(
                    title: "Particle Density",
                    value: $settings.particleDensity,
                    range: 0.2...2.0,
                    subtitle: settings.particleDensity > 1.5 ? "High" : settings.particleDensity > 0.8 ? "Normal" : "Low",
                    themeColor: themeManager.currentTheme.primaryColor
                )
                
                SettingsSlider(
                    title: "Glow Intensity",
                    value: $settings.glowIntensity,
                    range: 0.2...1.0,
                    subtitle: "\(Int(settings.glowIntensity * 100))%",
                    themeColor: themeManager.currentTheme.primaryColor
                )
                
                SettingsToggle(
                    title: "Haptic Feedback",
                    subtitle: "Tactile responses for interactions",
                    isOn: $settings.enableHapticFeedback,
                    themeColor: themeManager.currentTheme.primaryColor
                )
                
                SettingsToggle(
                    title: "Dark Mode Only",
                    subtitle: "Maintain consistent dark interface",
                    isOn: $settings.darkModeOnly,
                    themeColor: themeManager.currentTheme.primaryColor
                )
            }
        }
    }
    
    private var permissionsSection: some View {
        SettingsSection(
            title: "Permissions & Privacy",
            icon: "lock.shield",
            themeColor: themeManager.currentTheme.primaryColor
        ) {
            VStack(spacing: 15) {
                SettingsButton(
                    title: "Manage Permissions",
                    subtitle: "Review microphone, location, and other access",
                    themeColor: themeManager.currentTheme.primaryColor,
                    action: { showingPermissionsSheet = true }
                )
                
                SettingsToggle(
                    title: "Auto Location Updates",
                    subtitle: "Allow location-based responses",
                    isOn: $settings.autoLocationUpdates,
                    themeColor: themeManager.currentTheme.primaryColor
                )
                
                SettingsToggle(
                    title: "Notifications",
                    subtitle: "Reminders and system alerts",
                    isOn: $settings.enableNotifications,
                    themeColor: themeManager.currentTheme.primaryColor
                )
                
                SettingsToggle(
                    title: "Auto-Backup Conversations",
                    subtitle: "Save chat history to iCloud",
                    isOn: $settings.autoBackupConversations,
                    themeColor: themeManager.currentTheme.primaryColor
                )
                
                SettingsToggle(
                    title: "Clear Data on Exit",
                    subtitle: "Remove conversation history when closing",
                    isOn: $settings.clearDataOnExit,
                    themeColor: themeManager.currentTheme.primaryColor
                )
                
                SettingsToggle(
                    title: "Usage Analytics",
                    subtitle: "Help improve J.A.R.V.I.S. performance",
                    isOn: $settings.enableAnalytics,
                    themeColor: themeManager.currentTheme.primaryColor
                )
            }
        }
    }
    
    private var advancedSection: some View {
        SettingsSection(
            title: "Advanced",
            icon: "gearshape.2",
            themeColor: themeManager.currentTheme.primaryColor
        ) {
            VStack(spacing: 15) {
                DisclosureGroup("Advanced Settings", isExpanded: $showAdvancedSettings) {
                    VStack(spacing: 15) {
                        SettingsToggle(
                            title: "Offline Mode",
                            subtitle: "Use on-device processing only",
                            isOn: $settings.offlineMode,
                            themeColor: themeManager.currentTheme.primaryColor
                        )
                        
                        SettingsToggle(
                            title: "Debug Mode",
                            subtitle: "Show detailed system information",
                            isOn: $settings.enableDebugMode,
                            themeColor: themeManager.currentTheme.primaryColor
                        )
                        
                        SettingsButton(
                            title: "Clear Cache",
                            subtitle: "Free up storage space",
                            themeColor: themeManager.currentTheme.primaryColor,
                            action: clearCache
                        )
                        
                        SettingsButton(
                            title: "Re-cache Voice Greeting",
                            subtitle: "Download fresh AI voice greeting",
                            themeColor: themeManager.currentTheme.primaryColor,
                            action: recacheGreeting
                        )
                        
                        SettingsButton(
                            title: "Export Settings",
                            subtitle: "Save current configuration",
                            themeColor: themeManager.currentTheme.primaryColor,
                            action: exportSettings
                        )
                        
                        SettingsButton(
                            title: "Import Settings",
                            subtitle: "Restore from backup",
                            themeColor: themeManager.currentTheme.primaryColor,
                            action: importSettings
                        )
                    }
                    .padding(.top, 10)
                }
                .accentColor(themeManager.currentTheme.primaryColor)
            }
        }
    }
    
    private var aboutSection: some View {
        SettingsSection(
            title: "About & Support",
            icon: "info.circle",
            themeColor: themeManager.currentTheme.primaryColor
        ) {
            VStack(spacing: 15) {
                SettingsButton(
                    title: "Version Information",
                    subtitle: "J.A.R.V.I.S. v2.1.0 (Build 2024.12)",
                    themeColor: themeManager.currentTheme.primaryColor,
                    action: { }
                )
                
                SettingsButton(
                    title: "What's New",
                    subtitle: "Latest features and improvements",
                    themeColor: themeManager.currentTheme.primaryColor,
                    action: showWhatsNew
                )
                
                SettingsButton(
                    title: "User Guide",
                    subtitle: "Learn how to get the most from J.A.R.V.I.S.",
                    themeColor: themeManager.currentTheme.primaryColor,
                    action: openUserGuide
                )
                
                SettingsButton(
                    title: "Report Issue",
                    subtitle: "Help us improve the experience",
                    themeColor: themeManager.currentTheme.primaryColor,
                    action: reportIssue
                )
                
                SettingsButton(
                    title: "Privacy Policy",
                    subtitle: "How we protect your data",
                    themeColor: themeManager.currentTheme.primaryColor,
                    action: openPrivacyPolicy
                )
                
                Button(action: { showingResetAlert = true }) {
                    HStack {
                        Image(systemName: "arrow.clockwise.circle")
                            .foregroundColor(.red)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Reset All Settings")
                                .foregroundColor(.red)
                                .fontWeight(.medium)
                            Text("Restore factory defaults")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.clear)
                            .glassEffect()
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    // MARK: - Actions
    private func signOut() {
        do {
            try Auth.auth().signOut()
            HapticManager.shared.notification(type: .success)
        } catch {
            print("Error signing out: \(error.localizedDescription)")
            HapticManager.shared.notification(type: .error)
        }
    }
    
    private func resetAllSettings() {
        settings.voiceActivationEnabled = true
        settings.hotwordSensitivity = 0.7
        settings.voiceVolume = 0.8
        settings.speechRate = 0.52
        settings.useElevenLabsVoice = true
        settings.selectedVoice = "Rachel"
        settings.enableHapticFeedback = true
        settings.autoLocationUpdates = true
        settings.enableNotifications = true
        settings.darkModeOnly = true
        settings.particleDensity = 1.0
        settings.glowIntensity = 0.8
        settings.conversationTimeout = 5.0
        settings.clearDataOnExit = false
        settings.enableAnalytics = false
        settings.offlineMode = false
        settings.enableDebugMode = false
        settings.autoBackupConversations = true
        settings.voiceGender = "British Male"
        
        // Reset theme
        themeManager.setTheme(.classicBlue)
        
        // Haptic feedback
        HapticManager.shared.impact(style: .medium)
    }
    
    private func clearCache() {
        // Clear cached data
        UserDefaults.standard.removeObject(forKey: "jarvis_greeting_audio")
        
        HapticManager.shared.impact(style: .light)
    }
    
    private func recacheGreeting() {
        // Re-download greeting audio
        UserDefaults.standard.removeObject(forKey: "jarvis_greeting_audio")
        
        HapticManager.shared.impact(style: .light)
    }
    
    private func exportSettings() {
        // Export settings logic
        HapticManager.shared.impact(style: .light)
    }
    
    private func importSettings() {
        // Import settings logic
        HapticManager.shared.impact(style: .light)
    }
    
    private func showWhatsNew() {
        // Show what's new
    }
    
    private func openUserGuide() {
        // Open user guide
    }
    
    private func reportIssue() {
        // Report issue
    }
    
    private func openPrivacyPolicy() {
        // Open privacy policy
    }
}

// MARK: - Settings Components
struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    let themeColor: Color
    let content: Content
    
    init(title: String, icon: String, themeColor: Color, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.themeColor = themeColor
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(themeColor)
                    .font(.title2)
                
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
            }
            
            VStack(spacing: 12) {
                content
            }
            .padding()
            .background(
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.clear)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
                    
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.gray.opacity(0.5), lineWidth: 0.5)
                }
            )
        }
    }
}

struct SettingsToggle: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    let themeColor: Color
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundColor(.white)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .tint(themeColor)
                .onChange(of: isOn) { _ in
                    if JARVISSettings.shared.enableHapticFeedback {
                        HapticManager.shared.impact(style: .light)
                    }
                }
        }
    }
}

struct SettingsSlider: View {
    let title: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let subtitle: String
    let themeColor: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .foregroundColor(.white)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Slider(value: $value, in: range)
                .tint(themeColor)
                .onChange(of: value) { _ in
                    if JARVISSettings.shared.enableHapticFeedback {
                        HapticManager.shared.selection()
                    }
                }
        }
    }
}

struct SettingsPicker: View {
    let title: String
    @Binding var selection: String
    let options: [String]
    let themeColor: Color
    
    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.white)
                .fontWeight(.medium)
            
            Spacer()
            
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .tint(themeColor)
            .onChange(of: selection) { _ in
                if JARVISSettings.shared.enableHapticFeedback {
                    HapticManager.shared.impact(style: .light)
                }
            }
        }
    }
}

struct SettingsButton: View {
    let title: String
    let subtitle: String
    let themeColor: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            if JARVISSettings.shared.enableHapticFeedback {
                HapticManager.shared.impact(style: .light)
            }
            action()
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundColor(.white)
                        .fontWeight(.medium)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
            .padding()
            .background(
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.clear)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
                    
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.5), lineWidth: 0.5)
                }
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Permissions Help View
struct PermissionsHelpView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var themeManager = ThemeManager.shared
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    PermissionHelpItem(
                        icon: "mic",
                        title: "Microphone",
                        description: "Required for voice commands and conversations with J.A.R.V.I.S.",
                        status: "Granted",
                        themeColor: themeManager.currentTheme.primaryColor
                    )
                    
                    PermissionHelpItem(
                        icon: "location",
                        title: "Location",
                        description: "Enables location-based responses like finding nearby places.",
                        status: "Granted",
                        themeColor: themeManager.currentTheme.primaryColor
                    )
                    
                    PermissionHelpItem(
                        icon: "music.note",
                        title: "Media Library",
                        description: "Allows J.A.R.V.I.S. to control and play your music.",
                        status: "Granted",
                        themeColor: themeManager.currentTheme.primaryColor
                    )
                    
                    PermissionHelpItem(
                        icon: "calendar",
                        title: "Calendar",
                        description: "Lets J.A.R.V.I.S. create events and check your schedule.",
                        status: "Granted",
                        themeColor: themeManager.currentTheme.primaryColor
                    )
                    
                    PermissionHelpItem(
                        icon: "bell",
                        title: "Notifications",
                        description: "Enables reminders and system alerts from J.A.R.V.I.S.",
                        status: "Granted",
                        themeColor: themeManager.currentTheme.primaryColor
                    )
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Manage Permissions")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        Text("To modify these permissions, go to Settings > Privacy & Security > [Permission Type] and toggle J.A.R.V.I.S.")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        Button("Open Settings") {
                            if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(settingsUrl)
                            }
                        }
                        .foregroundColor(themeManager.currentTheme.primaryColor)
                        .padding(.top, 10)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.clear)
                            .glassEffect()
                    )
                }
                .padding()
            }
            .background(Color.black)
            .navigationTitle("Permissions")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Done") { dismiss() })
            .preferredColorScheme(.dark)
        }
    }
}

struct PermissionHelpItem: View {
    let icon: String
    let title: String
    let description: String
    let status: String
    let themeColor: Color
    
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: icon)
                .foregroundColor(themeColor)
                .font(.title2)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .foregroundColor(.white)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Text(status)
                .font(.caption)
                .foregroundColor(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.2))
                .cornerRadius(8)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.clear)
                .glassEffect()
        )
    }
}

class ContactsImporter {
    private let functions = Functions.functions()
    
    func importVCardFile(vcardContent: String, completion: @escaping (Bool, String) -> Void) {
        let data = ["vcardContent": vcardContent]
        
        functions.httpsCallable("importContacts").call(data) { result, error in
            if let error = error {
                print("Import error: \(error.localizedDescription)")
                completion(false, "Failed to import contacts: \(error.localizedDescription)")
                return
            }
            
            guard let data = result?.data as? [String: Any],
                  let success = data["success"] as? Bool,
                  let message = data["message"] as? String else {
                completion(false, "Invalid response from server")
                return
            }
            
            completion(success, message)
        }
    }
    
    func presentVCardPicker(from viewController: UIViewController, completion: @escaping (Bool, String) -> Void) {
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.init(filenameExtension: "vcf")!])
        documentPicker.delegate = VCardPickerDelegate(completion: completion, importer: self)
        viewController.present(documentPicker, animated: true)
    }
}

class VCardPickerDelegate: NSObject, UIDocumentPickerDelegate {
    private let completion: (Bool, String) -> Void
    private let importer: ContactsImporter
    
    init(completion: @escaping (Bool, String) -> Void, importer: ContactsImporter) {
        self.completion = completion
        self.importer = importer
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else {
            completion(false, "No file selected")
            return
        }
        
        do {
            let vcardContent = try String(contentsOf: url, encoding: .utf8)
            importer.importVCardFile(vcardContent: vcardContent, completion: completion)
        } catch {
            completion(false, "Failed to read vCard file: \(error.localizedDescription)")
        }
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        completion(false, "Import cancelled")
    }
}

// Add this to your settings or profile view:
/*
Button("Import Contacts from vCard") {
    let importer = ContactsImporter()
    importer.presentVCardPicker(from: UIHostingController(rootView: self)) { success, message in
        DispatchQueue.main.async {
            // Show alert with result
            print("Import result: \(success) - \(message)")
        }
    }
}
*/

#Preview {
    JARVISSettingsView()
}
