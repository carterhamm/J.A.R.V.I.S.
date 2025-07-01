//
//  KnowledgeView.swift
//  JARVIS
//
//  Enhanced with better microphone handling and theme support
//

import SwiftUI
import SceneKit
import UIKit
import Speech
import AVFoundation
import FirebaseFunctions
import EventKit
import UserNotifications
import Network
import MediaPlayer
import MapKit
import CoreLocation
import FoundationModels

// MARK: - Enhanced Haptic Feedback Helper
class HapticManager {
    static let shared = HapticManager()
    
    private init() {}
    
    func impact(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard JARVISSettings.shared.enableHapticFeedback else { return }
        DispatchQueue.main.async {
            let generator = UIImpactFeedbackGenerator(style: style)
            generator.prepare()
            generator.impactOccurred()
        }
    }
    
    func notification(type: UINotificationFeedbackGenerator.FeedbackType) {
        guard JARVISSettings.shared.enableHapticFeedback else { return }
        DispatchQueue.main.async {
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(type)
        }
    }
    
    func selection() {
        guard JARVISSettings.shared.enableHapticFeedback else { return }
        DispatchQueue.main.async {
            let generator = UISelectionFeedbackGenerator()
            generator.prepare()
            generator.selectionChanged()
        }
    }
}

// MARK: - Notification helpers
extension Notification.Name {
    static let showMessages = Notification.Name("ShowMessages")
    static let jarvisResponse = Notification.Name("JarvisResponse")
    static let locationRequest = Notification.Name("LocationRequest")
}

// MARK: - Foundation Models helpers
enum FoundationLLM {
    static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    private static let session: LanguageModelSession? = {
        guard SystemLanguageModel.default.isAvailable else { return nil }
        return LanguageModelSession()
    }()

    static func respond(to prompt: String) async throws -> String {
        guard let session else {
            throw NSError(
                domain: "FoundationLLM",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "On‑device LLM not available"]
            )
        }
        let response = try await session.respond(to: prompt)
        return response.content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }
}

// MARK: - Enhanced J.A.R.V.I.S. ViewModel with better microphone handling
class JARVISViewModel: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, CLLocationManagerDelegate {
    @Published var showImages = false
    @Published var currentImages: [URL] = []
    @Published var lastUserQuery: String? = nil
    @Published var isOffline: Bool = false
    @Published var jarvisMessages: [(text: String, isUser: Bool)] = []
    @Published var microphoneAvailable: Bool = true
    @Published var microphoneError: String? = nil

    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechSynthesizer = AVSpeechSynthesizer()
    private let functions = Functions.functions()
    private var speechCompletion: (() -> Void)?
    private var silenceTimer: Timer?
    private var audioPlayer: AVAudioPlayer?
    private let eventStore = EKEventStore()
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "NetworkMonitor")
    private var cachedGreetingAudio: Data?
    private var isProcessingResponse = false
    private let locationManager = CLLocationManager()
    private let musicPlayer = MPMusicPlayerController.systemMusicPlayer
    private var shouldStartListening = true
    
    private let foundationOfflineAvailable = FoundationLLM.isAvailable

    override init() {
        super.init()
        speechSynthesizer.delegate = self
        locationManager.delegate = self
        requestPermissions()
        setupNetworkMonitoring()
        setupLocationServices()
        loadCachedGreeting()
        
        // Check microphone availability before starting
        checkMicrophoneAvailability { [weak self] available, error in
            DispatchQueue.main.async {
                self?.microphoneAvailable = available
                self?.microphoneError = error
                
                if available && self?.shouldStartListening == true {
                    self?.startHotwordListening()
                } else {
                    print("🎤 Microphone not available or in use: \(error ?? "Unknown error")")
                }
            }
        }
    }
    
    private func checkMicrophoneAvailability(completion: @escaping (Bool, String?) -> Void) {
        // First check permission
        switch AVAudioSession.sharedInstance().recordPermission {
        case .denied:
            completion(false, "Microphone permission denied")
            return
        case .undetermined:
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                if granted {
                    self.checkMicrophoneAvailability(completion: completion)
                } else {
                    completion(false, "Microphone permission denied")
                }
            }
            return
        case .granted:
            break
        @unknown default:
            completion(false, "Unknown permission state")
            return
        }
        
        // Check if microphone is available (not in use by another app)
        do {
            let session = AVAudioSession.sharedInstance()
            
            // Try to set category and activate session
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            
            // Test if we can create an audio engine input node
            let audioEngine = AVAudioEngine()
            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            
            // Try to install a tap to test availability
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { _, _ in
                // Just testing, don't process audio
            }
            
            // If we get here, microphone is available
            inputNode.removeTap(onBus: 0)
            completion(true, nil)
            
        } catch let error as NSError {
            var errorMessage = "Microphone unavailable"
            
            // Check for specific error codes
            if error.domain == NSOSStatusErrorDomain {
                switch error.code {
                case AVAudioSession.ErrorCode.resourceNotAvailable.rawValue:
                    errorMessage = "Microphone in use by another app"
                case AVAudioSession.ErrorCode.incompatibleCategory.rawValue:
                    errorMessage = "Audio session category conflict"
                default:
                    errorMessage = "Audio system error: \(error.code)"
                }
            } else {
                errorMessage = error.localizedDescription
            }
            
            completion(false, errorMessage)
        }
    }
    
    private func setupLocationServices() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.startUpdatingLocation()
    }
    
    func clearCachedGreeting() {
        UserDefaults.standard.removeObject(forKey: "jarvis_greeting_audio")
        cachedGreetingAudio = nil
        print("Cleared cached greeting audio")
    }

    private func setupNetworkMonitoring() {
        monitor.pathUpdateHandler = { path in
            DispatchQueue.main.async {
                self.isOffline = path.status != .satisfied
                print("Network status: \(path.status == .satisfied ? "Online" : "Offline")")
            }
        }
        monitor.start(queue: monitorQueue)
    }
    
    private func loadCachedGreeting() {
        if let cachedData = UserDefaults.standard.data(forKey: "jarvis_greeting_audio") {
            cachedGreetingAudio = cachedData
            print("Loaded cached greeting audio")
        } else {
            generateAndCacheGreeting()
        }
    }
    
    private func generateAndCacheGreeting() {
        let greeting = "Hello, sir. At your service."
        functions.httpsCallable("onMessage").call(["message": greeting]) { result, error in
            if let data = result?.data as? [String: Any],
               let audioBase64 = data["audio"] as? String,
               let audioData = self.base64ToData(audioBase64) {
                self.cachedGreetingAudio = audioData
                UserDefaults.standard.set(audioData, forKey: "jarvis_greeting_audio")
                print("Cached greeting audio for future use")
            }
        }
    }
    
    private func base64ToData(_ base64String: String) -> Data? {
        if base64String.hasPrefix("data:audio/mpeg;base64,") {
            let base64 = String(base64String.dropFirst("data:audio/mpeg;base64,".count))
            return Data(base64Encoded: base64)
        } else {
            return Data(base64Encoded: base64String)
        }
    }

    func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { status in
            if status != .authorized {
                print("Speech recognition authorization denied: \(status)")
            }
        }
        
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            if !granted {
                print("Microphone permission denied")
            }
        }
        
        eventStore.requestAccess(to: .event) { granted, error in
            if !granted {
                print("Calendar access denied: \(String(describing: error))")
            }
        }
        
        eventStore.requestAccess(to: .reminder) { granted, error in
            if !granted {
                print("Reminders access denied: \(String(describing: error))")
            }
        }
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if !granted {
                print("Notification permission denied: \(String(describing: error))")
            }
        }
        
        MPMediaLibrary.requestAuthorization { status in
            if status != .authorized {
                print("Media library access denied: \(status)")
            }
        }
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            try session.overrideOutputAudioPort(.speaker)
        } catch {
            print("Audio session config error: \(error)")
        }
    }

    func startHotwordListening() {
        // Check settings first
        guard JARVISSettings.shared.voiceActivationEnabled else {
            print("Voice activation disabled in settings")
            return
        }
        
        guard !isProcessingResponse else {
            print("Still processing response, skipping hotword listening")
            return
        }
        
        guard microphoneAvailable else {
            print("Microphone not available: \(microphoneError ?? "Unknown error")")
            return
        }
        
        stopListening()
        configureAudioSession()

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest?.shouldReportPartialResults = true
        recognitionRequest?.taskHint = .dictation

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        
        do {
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                self.recognitionRequest?.append(buffer)
            }
        } catch {
            print("Failed to install tap: \(error)")
            // Retry after delay if tap installation fails
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.checkMicrophoneAvailability { available, error in
                    DispatchQueue.main.async {
                        self.microphoneAvailable = available
                        self.microphoneError = error
                        if available {
                            self.startHotwordListening()
                        }
                    }
                }
            }
            return
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            print("Hotword listening started")
        } catch {
            print("Hotword AudioEngine start error: \(error)")
            microphoneAvailable = false
            microphoneError = error.localizedDescription
            return
        }

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest!) { result, error in
            if let result = result {
                let transcript = result.bestTranscription.formattedString.lowercased()
                if transcript.contains("jarvis") {
                    self.stopListening()
                    self.wakeJarvis()
                }
            }
            if let error = error {
                print("Hotword recognition error: \(error.localizedDescription)")
                if (error as NSError).code != 1110 {
                    self.stopListening()
                    // Check if microphone is still available before retrying
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.checkMicrophoneAvailability { available, error in
                            DispatchQueue.main.async {
                                self.microphoneAvailable = available
                                self.microphoneError = error
                                if available {
                                    self.startHotwordListening()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func wakeJarvis() {
        isProcessingResponse = true
        
        if let cachedAudio = cachedGreetingAudio {
            print("Playing cached greeting")
            playAudioFromData(cachedAudio) {
                self.startConversationListening()
            }
        } else {
            speak("Hello, sir. At your service.") {
                self.startConversationListening()
            }
        }
    }
    
    func startConversationListening() {
        guard microphoneAvailable else {
            print("Cannot start conversation listening: microphone unavailable")
            isProcessingResponse = false
            restartHotword()
            return
        }
        
        stopListening()
        configureAudioSession()

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest?.shouldReportPartialResults = true
        recognitionRequest?.taskHint = .dictation

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        
        do {
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                self.recognitionRequest?.append(buffer)
            }
        } catch {
            print("Failed to install conversation tap: \(error)")
            isProcessingResponse = false
            restartHotword()
            return
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            print("Conversation listening started")
        } catch {
            print("Conversation AudioEngine start error: \(error)")
            isProcessingResponse = false
            restartHotword()
            return
        }

        var lastTranscript = ""
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest!) { result, error in
            if let result = result {
                let transcript = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                if !transcript.isEmpty && transcript != lastTranscript {
                    lastTranscript = transcript
                    print("Transcript updated: \(transcript)")
                    DispatchQueue.main.async {
                        self.lastUserQuery = transcript
                    }
                    self.resetSilenceTimer(transcript)
                }
            }
            if let error = error {
                print("Conversation recognition error: \(error.localizedDescription)")
                if (error as NSError).code != 1110 {
                    self.stopListening()
                    self.isProcessingResponse = false
                    self.restartHotword()
                }
            }
        }
    }

    private func resetSilenceTimer(_ transcript: String) {
        silenceTimer?.invalidate()
        let timeout = TimeInterval(JARVISSettings.shared.conversationTimeout)
        silenceTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { _ in
            print("Silence detected after \(timeout)s, sending: \(transcript)")
            self.stopListening()
            self.sendToJarvis(transcript)
        }
    }

    func sendToJarvis(_ text: String) {
        print("Sending to Jarvis: \(text)")
        isProcessingResponse = true
        
        DispatchQueue.main.async {
            self.jarvisMessages.append((text: text, isUser: true))
            NotificationCenter.default.post(name: .jarvisResponse, object: nil, userInfo: ["message": text, "isUser": true])
        }
        
        if isOffline || JARVISSettings.shared.offlineMode {
            print("Using offline processing")
            processOffline(text)
            return
        }
        
        // Enhanced message data with timezone and location info
        let messageData: [String: Any] = [
            "message": text,
            "timezone": TimeZone.current.identifier,
            "location": locationManager.location?.description ?? ""
        ]
        
        print("Sending data: \(messageData)")
        
        functions.httpsCallable("onMessage").call(messageData) { result, error in
            if let error = error as NSError? {
                print("Cloud function error: \(error.localizedDescription)")
                
                if self.isOffline || JARVISSettings.shared.offlineMode {
                    self.processOffline(text)
                } else {
                    let errorResponse = "I apologize, I'm having trouble connecting to my systems."
                    DispatchQueue.main.async {
                        self.jarvisMessages.append((text: errorResponse, isUser: false))
                        NotificationCenter.default.post(name: .jarvisResponse, object: nil, userInfo: ["message": errorResponse, "isUser": false])
                    }
                    self.speak(errorResponse) {
                        self.isProcessingResponse = false
                        self.restartHotword()
                    }
                }
                return
            }
            
            guard let data = result?.data as? [String: Any] else {
                print("Invalid response format")
                let errorResponse = "I didn't understand the response format."
                DispatchQueue.main.async {
                    self.jarvisMessages.append((text: errorResponse, isUser: false))
                    NotificationCenter.default.post(name: .jarvisResponse, object: nil, userInfo: ["message": errorResponse, "isUser": false])
                }
                self.speak(errorResponse) {
                    self.isProcessingResponse = false
                    self.restartHotword()
                }
                return
            }
            
            print("Received response: \(data)")
            
            DispatchQueue.main.async {
                if let urls = data["images"] as? [String] {
                    self.currentImages = urls.compactMap { URL(string: $0) }
                    self.showImages = !self.currentImages.isEmpty
                    print("Updated images: \(self.currentImages)")
                } else {
                    self.currentImages = []
                    self.showImages = false
                }
            }
            
            if let actions = data["actions"] as? [String: String] {
                self.handleActions(actions)
            }
            
            if let reply = data["text"] as? String {
                print("Speaking reply: \(reply)")
                
                DispatchQueue.main.async {
                    self.jarvisMessages.append((text: reply, isUser: false))
                    NotificationCenter.default.post(name: .jarvisResponse, object: nil, userInfo: ["message": reply, "isUser": false])
                }
                
                if let audioBase64 = data["audio"] as? String, JARVISSettings.shared.useElevenLabsVoice {
                    print("Playing ElevenLabs audio")
                    self.playAudioFromBase64(audioBase64) {
                        self.isProcessingResponse = false
                        self.startConversationListening()
                    }
                } else {
                    self.speak(reply) {
                        self.isProcessingResponse = false
                        self.startConversationListening()
                    }
                }
            } else if let errorMessage = data["error"] as? String {
                print("Server returned error: \(errorMessage)")
                let errorResponse = "I encountered an error: \(errorMessage)"
                DispatchQueue.main.async {
                    self.jarvisMessages.append((text: errorResponse, isUser: false))
                    NotificationCenter.default.post(name: .jarvisResponse, object: nil, userInfo: ["message": errorResponse, "isUser": false])
                }
                self.speak(errorResponse) {
                    self.isProcessingResponse = false
                    self.restartHotword()
                }
            } else {
                print("No text in response")
                self.isProcessingResponse = false
                self.startConversationListening()
            }
        }
    }
    
    // MARK: - Fixed time detection
    private func isTimeQuery(_ text: String) -> Bool {
        let lower = text.lowercased()
        
        let movieTerms = ["movie", "film", "runtime", "duration", "long", "length", "minutes", "hours"]
        if movieTerms.contains(where: { lower.contains($0) }) {
            return false
        }
        
        let timePatterns = [
            "what time is it",
            "current time",
            "tell me the time",
            "what's the time",
            "time right now"
        ]
        
        return timePatterns.contains { lower.contains($0) }
    }
    
    private func processOffline(_ text: String) {
        let lower = text.lowercased()
        
        if isTimeQuery(text) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.timeZone = TimeZone.current
            let timeString = formatter.string(from: Date())
            let timeZoneName = TimeZone.current.localizedName(for: .standard, locale: Locale.current) ?? TimeZone.current.identifier
            let response = "The current time is \(timeString) \(timeZoneName), sir."
            respondOffline(response)
            return
        }
        
        if lower.contains("where is") || lower.contains("map") || (lower.contains("nearest") || lower.contains("closest")) && !lower.contains("movie") {
            handleMapQuery(text)
            return
        }
        
        if lower.contains("play") && (lower.contains("music") || lower.contains("song") || lower.contains("artist") || lower.contains("album")) {
            handleMusicAction(text)
            if !lower.contains("album art") && !lower.contains("cover") {
                let response = "Certainly, sir. I'll handle your music request."
                respondOffline(response)
            }
            return
        }
        
        if (lower.contains("music") || lower.contains("song")) && (lower.contains("stop") || lower.contains("pause") || lower.contains("next") || lower.contains("skip") || lower.contains("previous")) {
            handleMusicAction(text)
            let response = "Music playback adjusted, sir."
            respondOffline(response)
            return
        }
        
        if foundationOfflineAvailable {
            Task {
                do {
                    let prompt = """
                    You are J.A.R.V.I.S., Tony Stark's AI assistant. Answer the following question in character:
                    
                    User: \(text)
                    
                    Important: If the user is asking about:
                    - Movie runtime, duration, or length: Explain that you need internet access to look up current movie information
                    - Album art or music covers: Explain that you cannot display images in offline mode
                    - Any specific factual information you don't have: Be honest that you need internet access for that information
                    
                    Provide a helpful, accurate response in J.A.R.V.I.S.'s characteristic British style. Keep it concise but informative.
                    """
                    
                    let assistantReply = try await FoundationLLM.respond(to: prompt)
                    
                    DispatchQueue.main.async {
                        self.respondOffline(assistantReply)
                        
                        if text.lowercased().contains("reminder") {
                            self.createReminder(text)
                        } else if text.lowercased().contains("calendar") {
                            self.createCalendarEvent(text)
                        }
                    }
                } catch {
                    print("FoundationLLM error:", error)
                    self.respondOffline("I apologize, sir. I'm having difficulty processing that request offline. Perhaps you could rephrase it?")
                }
            }
        } else {
            respondOffline("I'm operating in offline mode without advanced language capabilities, sir. I can still help with basic tasks like playing music, setting reminders, and checking the time.")
        }
    }
    
    // MARK: - Fixed location handling
    private func handleMapQuery(_ text: String) {
        let lower = text.lowercased()
        
        if lower.contains("nearest") || lower.contains("closest") {
            guard let userLocation = locationManager.location else {
                respondOffline("I need access to your location to find nearby places, sir.")
                return
            }
            
            let searchQuery: String
            if lower.contains("airport") {
                searchQuery = "airport"
            } else if lower.contains("hospital") {
                searchQuery = "hospital"
            } else if lower.contains("restaurant") {
                searchQuery = "restaurant"
            } else if lower.contains("gas") || lower.contains("petrol") {
                searchQuery = "gas station"
            } else {
                searchQuery = text
                    .replacingOccurrences(of: "(?i)nearest|closest|find|show me the", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            findNearestLocation(searchQuery: searchQuery, userLocation: userLocation)
        } else {
            let locationQuery = text
                .replacingOccurrences(of: "(?i)where is|map of|show me|the map of", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            respondOffline("I'll find that location for you, sir.")
            
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .locationRequest, object: nil, userInfo: ["query": locationQuery])
            }
        }
    }
    
    private func findNearestLocation(searchQuery: String, userLocation: CLLocation) {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchQuery
        request.region = MKCoordinateRegion(
            center: userLocation.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
        
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            guard let response = response, !response.mapItems.isEmpty else {
                self.respondOffline("I couldn't find any \(searchQuery) nearby, sir.")
                return
            }
            
            let sorted = response.mapItems.sorted { item1, item2 in
                let dist1 = item1.placemark.location?.distance(from: userLocation) ?? Double.infinity
                let dist2 = item2.placemark.location?.distance(from: userLocation) ?? Double.infinity
                return dist1 < dist2
            }
            
            if let nearest = sorted.first,
               let location = nearest.placemark.location {
                let distance = location.distance(from: userLocation)
                let distanceInMiles = distance / 1609.34
                
                let response = "The nearest \(searchQuery) is \(nearest.name ?? "unnamed"), approximately \(String(format: "%.1f", distanceInMiles)) miles away, sir."
                self.respondOffline(response)
                
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .locationRequest, object: nil, userInfo: [
                        "query": searchQuery,
                        "coordinate": location.coordinate,
                        "name": nearest.name ?? searchQuery
                    ])
                }
            }
        }
    }
    
    private func respondOffline(_ response: String) {
        DispatchQueue.main.async {
            self.jarvisMessages.append((text: response, isUser: false))
            NotificationCenter.default.post(name: .jarvisResponse, object: nil, userInfo: ["message": response, "isUser": false])
        }
        
        speak(response) {
            self.isProcessingResponse = false
            self.startConversationListening()
        }
    }

    private func handleActions(_ actions: [String: String]) {
        if let rem = actions["reminder"] { createReminder(rem) }
        if let ev = actions["calendar"]  { createCalendarEvent(ev) }
        if let note = actions["note"]    { createNote(note) }
        if let music = actions["music"]  { handleMusicAction(music) }
        if let maps = actions["maps"]    { handleMapsAction(maps) }
    }
    
    private func handleMusicAction(_ action: String) {
        let lower = action.lowercased()
        
        stopListening()
        
        if lower.contains("play") {
            MPMediaLibrary.requestAuthorization { status in
                if status == .authorized {
                    DispatchQueue.main.async {
                        if lower.contains("shuffle") && !lower.contains("by") {
                            let query = MPMediaQuery.songs()
                            self.musicPlayer.setQueue(with: query)
                            self.musicPlayer.shuffleMode = .songs
                            self.musicPlayer.play()
                        } else {
                            let searchTerms = self.extractMusicSearchTerms(from: action)
                            
                            if let terms = searchTerms {
                                var found = false
                                
                                if !found {
                                    let songPredicate = MPMediaPropertyPredicate(
                                        value: terms.query,
                                        forProperty: MPMediaItemPropertyTitle,
                                        comparisonType: .contains
                                    )
                                    let songQuery = MPMediaQuery()
                                    songQuery.addFilterPredicate(songPredicate)
                                    
                                    if let items = songQuery.items, !items.isEmpty {
                                        let filteredItems: [MPMediaItem]
                                        if let artist = terms.artist {
                                            filteredItems = items.filter { item in
                                                item.artist?.lowercased().contains(artist.lowercased()) ?? false
                                            }
                                        } else {
                                            filteredItems = items
                                        }
                                        
                                        if !filteredItems.isEmpty {
                                            let collection = MPMediaItemCollection(items: filteredItems)
                                            self.musicPlayer.setQueue(with: collection)
                                            self.musicPlayer.play()
                                            found = true
                                        }
                                    }
                                }
                                
                                if !found && terms.artist != nil {
                                    let artistPredicate = MPMediaPropertyPredicate(
                                        value: terms.artist!,
                                        forProperty: MPMediaItemPropertyArtist,
                                        comparisonType: .contains
                                    )
                                    let artistQuery = MPMediaQuery()
                                    artistQuery.addFilterPredicate(artistPredicate)
                                    
                                    if let items = artistQuery.items, !items.isEmpty {
                                        let collection = MPMediaItemCollection(items: items)
                                        self.musicPlayer.setQueue(with: collection)
                                        self.musicPlayer.shuffleMode = .songs
                                        self.musicPlayer.play()
                                        found = true
                                    }
                                }
                                
                                if !found {
                                    let query = MPMediaQuery.songs()
                                    self.musicPlayer.setQueue(with: query)
                                    self.musicPlayer.shuffleMode = .songs
                                    self.musicPlayer.play()
                                }
                            } else {
                                self.musicPlayer.play()
                            }
                        }
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                            self.isProcessingResponse = false
                            self.startHotwordListening()
                        }
                    }
                } else {
                    print("Music library authorization denied")
                    self.speak("I need permission to access your music library, sir.") {
                        self.isProcessingResponse = false
                        self.restartHotword()
                    }
                }
            }
        } else if lower.contains("pause") {
            musicPlayer.pause()
            isProcessingResponse = false
            restartHotword()
        } else if lower.contains("next") || lower.contains("skip") {
            musicPlayer.skipToNextItem()
            isProcessingResponse = false
            restartHotword()
        } else if lower.contains("previous") || lower.contains("back") {
            musicPlayer.skipToPreviousItem()
            isProcessingResponse = false
            restartHotword()
        } else if lower.contains("stop") {
            musicPlayer.stop()
            isProcessingResponse = false
            restartHotword()
        }
    }
    
    private func extractMusicSearchTerms(from action: String) -> (query: String, artist: String?)? {
        let lower = action.lowercased()
        var query = ""
        var artist: String? = nil
        
        if let byIndex = lower.range(of: " by ") {
            let beforeBy = String(lower[..<byIndex.lowerBound])
            let afterBy = String(lower[byIndex.upperBound...])
            
            let songWords = beforeBy.components(separatedBy: " ")
            let skipWords = ["play", "the", "song", "track"]
            query = songWords.filter { !skipWords.contains($0) }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            
            artist = afterBy.trimmingCharacters(in: .whitespaces)
        } else {
            let words = lower.components(separatedBy: " ")
            let skipWords = ["play", "the", "some", "music", "song", "songs", "shuffle"]
            let relevantWords = words.filter { !skipWords.contains($0) }
            query = relevantWords.joined(separator: " ")
        }
        
        return query.isEmpty ? nil : (query: query, artist: artist)
    }
    
    private func handleMapsAction(_ destination: String) {
        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(destination) { placemarks, error in
            guard let placemark = placemarks?.first,
                  let location = placemark.location else {
                print("Failed to geocode destination: \(destination)")
                return
            }
            
            let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
            mapItem.name = destination
            mapItem.openInMaps(launchOptions: [
                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
            ])
        }
    }
    
    private func createReminder(_ reminderText: String) {
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = reminderText
        reminder.calendar = eventStore.defaultCalendarForNewReminders()
        if reminderText.lowercased().contains("tomorrow") {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute], from: Date().addingTimeInterval(86400))
        } else if reminderText.lowercased().contains("today") {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute], from: Date())
        }
        do { try eventStore.save(reminder, commit: true) } catch { print("Failed to create reminder: \(error)") }
    }
    
    private func createCalendarEvent(_ eventInfo: String) {
        let event = EKEvent(eventStore: eventStore)
        let comps = eventInfo.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        event.title = comps.first ?? "Event"
        if comps.count > 1 {
            if comps[1].lowercased().contains("tomorrow") { event.startDate = Date().addingTimeInterval(86400) }
            else if comps[1].lowercased().contains("today") { event.startDate = Date() }
            else { event.startDate = Date() }
        } else { event.startDate = Date() }
        event.endDate = event.startDate.addingTimeInterval(3600)
        event.calendar = eventStore.defaultCalendarForNewEvents
        do { try eventStore.save(event, span: .thisEvent) } catch { print("Failed to save event: \(error)") }
    }
    
    private func createNote(_ noteContent: String) {
        let content = UNMutableNotificationContent()
        content.title = "J.A.R.V.I.S. Note"
        content.body = noteContent
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let e = error { print("Failed to create note: \(e)") }
        }
    }

    private func speak(_ text: String, completion: @escaping () -> Void) {
        configureAudioSession()
        
        speechCompletion = completion
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-GB")
        utterance.rate = JARVISSettings.shared.speechRate
        utterance.volume = JARVISSettings.shared.voiceVolume
        speechSynthesizer.speak(utterance)
    }
    
    private func playAudioFromData(_ data: Data, completion: @escaping () -> Void) {
        configureAudioSession()
        
        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.volume = JARVISSettings.shared.voiceVolume
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            if let d = audioPlayer?.duration {
                DispatchQueue.main.asyncAfter(deadline: .now() + d) { completion() }
            } else { completion() }
        } catch {
            print("Error playing audio: \(error)")
            completion()
        }
    }
    
    private func playAudioFromBase64(_ base64String: String, completion: @escaping () -> Void) {
        guard let data = base64ToData(base64String) else {
            print("Failed to decode base64 audio")
            completion()
            return
        }
        playAudioFromData(data, completion: completion)
    }

    private func stopListening() {
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        silenceTimer?.invalidate()
        silenceTimer = nil
    }

    private func restartHotword() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.startHotwordListening()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        speechCompletion?()
        speechCompletion = nil
    }
    
    // MARK: - CLLocationManagerDelegate
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Location updates are handled automatically
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager failed with error: \(error)")
    }
}

// MARK: - Updated ImageView without background
struct ImageView: View {
    let imageURLs: [URL]
    @State private var currentIndex = 0

    var body: some View {
        TabView(selection: $currentIndex) {
            ForEach(imageURLs.indices, id: \.self) { index in
                AsyncImage(url: imageURLs[index]) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .aspectRatio(1, contentMode: .fit)
                            .padding(.horizontal, 20)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: UIScreen.main.bounds.width - 40, height: UIScreen.main.bounds.width - 40)
                            .clipped()
                            .cornerRadius(20)
                            .shadow(color: Color.black.opacity(0.6), radius: 10, x: 0, y: 0)
                    case .failure:
                        Color(red: 0, green: 0.6, blue: 0.8)
                            .aspectRatio(1, contentMode: .fit)
                            .cornerRadius(35)
                            .padding(.horizontal, 20)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    @unknown default:
                        EmptyView()
                    }
                }
                .tag(index)
            }
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
        .animation(.easeInOut, value: currentIndex)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Enhanced 3D Particle Sphere with Theme Support
struct AlternateParticleSphereView: UIViewRepresentable {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var settings: JARVISSettings
    
    func makeCoordinator() -> AlternateCoordinator {
        AlternateCoordinator(themeManager: themeManager, settings: settings)
    }
    
    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = .black
        scnView.allowsCameraControl = true

        let scene = SCNScene()
        context.coordinator.scene = scene

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0, 5)
        scene.rootNode.addChildNode(cameraNode)

        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light?.type = .omni
        lightNode.position = SCNVector3(0, 10, 10)
        scene.rootNode.addChildNode(lightNode)

        let ambientNode = SCNNode()
        ambientNode.light = SCNLight()
        ambientNode.light?.type = .ambient
        ambientNode.light?.color = UIColor(white: 0.3, alpha: 1.0)
        scene.rootNode.addChildNode(ambientNode)

        // Create particle containers
        context.coordinator.setupParticles(in: scene)

        let lookAt = SCNLookAtConstraint(target: context.coordinator.baseContainer)
        lookAt.isGimbalLockEnabled = true
        cameraNode.constraints = [lookAt]

        let spin = SCNAction.repeatForever(
            SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 30)
        )
        context.coordinator.baseContainer?.runAction(spin)
        context.coordinator.interiorContainer?.runAction(spin)
        context.coordinator.exteriorContainer?.runAction(spin)

        scnView.scene = scene
        scnView.isPlaying = true

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(AlternateCoordinator.handleLongPress(_:))
        )
        scnView.addGestureRecognizer(longPress)

        scnView.cameraControlConfiguration.allowsTranslation = false

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        // Update particles when theme or settings change
        context.coordinator.updateParticleColors()
    }

    class AlternateCoordinator: NSObject {
        var scene: SCNScene?
        var baseContainer: SCNNode?
        var interiorContainer: SCNNode?
        var exteriorContainer: SCNNode?
        var isZoomedIn = false
        
        private let themeManager: ThemeManager
        private let settings: JARVISSettings
        
        init(themeManager: ThemeManager, settings: JARVISSettings) {
            self.themeManager = themeManager
            self.settings = settings
        }
        
        func setupParticles(in scene: SCNScene) {
            // Base sphere points
            let baseContainer = SCNNode()
            let baseCount = Int(1500 * settings.particleDensity)
            for _ in 0..<baseCount {
                let theta = Float.random(in: 0...Float.pi)
                let phi = Float.random(in: 0...Float.pi * 2)
                let x = sin(theta) * cos(phi)
                let y = sin(theta) * sin(phi)
                let z = cos(theta)
                let sphere = SCNSphere(radius: 0.002)
                sphere.segmentCount = 6
                sphere.firstMaterial?.diffuse.contents = UIColor(themeManager.currentTheme.primaryColor)
                sphere.firstMaterial?.isDoubleSided = true
                sphere.firstMaterial?.lightingModel = .constant
                let node = SCNNode(geometry: sphere)
                node.position = SCNVector3(x, y, z)
                baseContainer.addChildNode(node)
            }
            scene.rootNode.addChildNode(baseContainer)
            self.baseContainer = baseContainer

            // Interior scatter
            let interiorContainer = SCNNode()
            let interiorCount = Int(1800 * settings.particleDensity)
            for _ in 0..<interiorCount {
                let u = Float.random(in: 0...1)
                let r = pow(u, 1/3) * 1.0
                let theta = Float.random(in: 0...Float.pi)
                let phi = Float.random(in: 0...Float.pi * 2)
                let x = r * sin(theta) * cos(phi)
                let y = r * sin(theta) * sin(phi)
                let z = r * cos(theta)
                let sphere = SCNSphere(radius: 0.002)
                sphere.segmentCount = 6
                sphere.firstMaterial?.diffuse.contents = UIColor(themeManager.currentTheme.primaryColor)
                sphere.firstMaterial?.isDoubleSided = true
                sphere.firstMaterial?.lightingModel = .constant
                let node = SCNNode(geometry: sphere)
                node.position = SCNVector3(x, y, z)
                interiorContainer.addChildNode(node)
            }
            scene.rootNode.addChildNode(interiorContainer)
            self.interiorContainer = interiorContainer

            // Exterior scatter
            let exteriorContainer = SCNNode()
            let exteriorCount = Int(500 * settings.particleDensity)
            for _ in 0..<exteriorCount {
                let theta = Float.random(in: 0...Float.pi)
                let phi = Float.random(in: 0...Float.pi * 2)
                let r = Float.random(in: 0.8...1.3)
                let x = r * sin(theta) * cos(phi)
                let y = r * sin(theta) * sin(phi)
                let z = r * cos(theta)
                let sphere = SCNSphere(radius: 0.0015)
                sphere.segmentCount = 6
                sphere.firstMaterial?.diffuse.contents = UIColor(themeManager.currentTheme.primaryColor)
                sphere.firstMaterial?.isDoubleSided = true
                sphere.firstMaterial?.lightingModel = .constant
                let node = SCNNode(geometry: sphere)
                node.position = SCNVector3(x, y, z)
                exteriorContainer.addChildNode(node)
            }
            scene.rootNode.addChildNode(exteriorContainer)
            self.exteriorContainer = exteriorContainer
        }
        
        func updateParticleColors() {
            let color = UIColor(themeManager.currentTheme.primaryColor)
            
            for container in [baseContainer, interiorContainer, exteriorContainer].compactMap({ $0 }) {
                for node in container.childNodes {
                    node.geometry?.firstMaterial?.diffuse.contents = color
                }
            }
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began else { return }

            HapticManager.shared.impact(style: .heavy)

            let scaleFactor: Float = isZoomedIn ? 0.2 : 5.0
            let duration: TimeInterval = 0.33
            
            for container in [baseContainer, interiorContainer, exteriorContainer].compactMap({ $0 }) {
                for node in container.childNodes {
                    let oldPos = node.position
                    let newPos = SCNVector3(oldPos.x * scaleFactor, oldPos.y * scaleFactor, oldPos.z * scaleFactor)
                    node.runAction(SCNAction.move(to: newPos, duration: duration))
                }
            }

            isZoomedIn.toggle()
            NotificationCenter.default.post(name: .showMessages, object: nil)
        }
    }
}

// MARK: - Enhanced Radial Menu Component with Theme Support
struct RadialMenuButton: View {
    @State private var isPressed = false
    @State private var dragLocation: CGPoint = .zero
    @State private var selectedOption: MenuOption? = nil
    @State private var lastHapticOption: MenuOption? = nil
    @State private var navigateToSettings = false
    @State private var navigateToProfile  = false
    @State private var navigateToOptions  = false
    @Binding var isVisible: Bool
    @EnvironmentObject var themeManager: ThemeManager
    
    enum MenuOption: String, CaseIterable {
        case settings = "Settings"
        case profile = "Profile"
        case options = "Options"
        
        var iconName: String {
            switch self {
            case .settings: return "gearshape"
            case .profile:  return "person.crop.circle"
            case .options:  return "ellipsis.circle"
            }
        }
        
        var angle: Double {
            switch self {
            case .settings: return 270
            case .profile: return 214
            case .options: return 180
            }
        }
        
        var offset: CGSize {
            let radius: Double = 115
            let radians = angle * .pi / 180
            return CGSize(
                width: cos(radians) * radius,
                height: sin(radians) * radius
            )
        }
    }
    
    var body: some View {
        ZStack {
            NavigationLink(destination: JARVISSettingsView(), isActive: $navigateToSettings) {
                EmptyView()
            }
            NavigationLink(destination: PeopleManagementView(), isActive: $navigateToProfile) {
                EmptyView()
            }
            NavigationLink(destination: Text("Options View"), isActive: $navigateToOptions) {
                EmptyView()
            }
            
            if isPressed {
                ForEach(MenuOption.allCases, id: \.self) { option in
                    HStack(spacing: 8) {
                        Image(systemName: option.iconName)
                            .imageScale(.large)
                            .scaleEffect(1.1)
                            .foregroundColor(themeManager.currentTheme.primaryColor)
                        Text(option.rawValue)
                            .font(.caption)
                            .scaleEffect(1.1)
                            .fontWeight(selectedOption == option ? .bold : .medium)
                            .foregroundColor(themeManager.currentTheme.primaryColor)
                            .padding(.horizontal, 2)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 80)
                            .fill(Color.clear)
                            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 80))
                    )
                    .scaleEffect(selectedOption == option ? 1.1 : 1.0)
                    .offset(option.offset)
                    .scaleEffect(isPressed ? 1.0 : 0.1)
                    .opacity(isPressed ? 1.0 : 0.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
                    .animation(.easeInOut(duration: 0.1), value: selectedOption)
                }
            }
            
            Circle()
                .fill(Color.clear)
                .glassEffect(.regular, in: Circle())
                .frame(width: isPressed ? 43.75 : 62.5, height: isPressed ? 43.75 : 62.5)
                .overlay(
                    Image(systemName: "arrow.up.left.circle.dotted")
                        .font(.system(size: isPressed ? 20 : 25, weight: .medium))
                        .foregroundColor(themeManager.currentTheme.primaryColor)
                )
                .scaleEffect(isPressed ? 0.9 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isPressed)
        }
        .opacity(isVisible ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.3), value: isVisible)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isPressed {
                        isPressed = true
                        HapticManager.shared.impact(style: .medium)
                    }
                    
                    dragLocation = value.location
                    let newSelectedOption = getSelectedOption(for: value.location)
                    
                    if newSelectedOption != selectedOption && newSelectedOption != nil {
                        if lastHapticOption != newSelectedOption {
                            HapticManager.shared.impact(style: .light)
                            lastHapticOption = newSelectedOption
                        }
                    }
                    
                    selectedOption = newSelectedOption
                }
                .onEnded { value in
                    if let selected = selectedOption {
                        HapticManager.shared.impact(style: .heavy)
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            switch selected {
                            case .settings:
                                navigateToSettings = true
                            case .profile:
                                navigateToProfile = true
                            case .options:
                                navigateToOptions = true
                            }
                        }
                    }
                    
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isPressed = false
                        selectedOption = nil
                        lastHapticOption = nil
                    }
                }
        )
    }
    
    private func getSelectedOption(for location: CGPoint) -> MenuOption? {
        let center = CGPoint(x: 25, y: 25)
        let distance = sqrt(pow(location.x - center.x, 2) + pow(location.y - center.y, 2))
        
        guard distance > 30 else { return nil }
        
        let angle = atan2(location.y - center.y, location.x - center.x) * 180 / .pi
        let normalizedAngle = angle < 0 ? angle + 360 : angle
        
        var closestOption: MenuOption?
        var closestDistance: Double = Double.infinity
        
        for option in MenuOption.allCases {
            let optionAngle = option.angle
            let angleDifference = min(
                abs(normalizedAngle - optionAngle),
                abs(normalizedAngle - optionAngle + 360),
                abs(normalizedAngle - optionAngle - 360)
            )
            
            if angleDifference < closestDistance && angleDifference < 45 {
                closestDistance = angleDifference
                closestOption = option
            }
        }
        
        return closestOption
    }
}

// MARK: - Main View with Theme Support
struct AlternateTestView: View {
    @State private var showMessages = false
    @State private var showRadialMenu = true
    @StateObject private var jarvis = JARVISViewModel()
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var settings = JARVISSettings.shared

    private var mainContent: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            AlternateParticleSphereView()
                .environmentObject(themeManager)
                .environmentObject(settings)
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
                // Microphone status indicator
                if !jarvis.microphoneAvailable {
                    HStack {
                        Image(systemName: "mic.slash")
                            .foregroundColor(.red)
                        Text(jarvis.microphoneError ?? "Microphone unavailable")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.7))
                    )
                    .padding(.top, 50)
                }
                
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
        .environmentObject(themeManager)
        .environmentObject(settings)
    }
}

extension View {
    func innerGlow(color: Color, lineWidth: CGFloat, blurRadius: CGFloat) -> some View {
        self
            .overlay(
                RoundedRectangle(
                    cornerRadius: UIScreen.main.displayCornerRadius,
                    style: .continuous
                )
                .stroke(color, lineWidth: lineWidth)
                .blur(radius: blurRadius)
            )
    }
}

// MARK: - Display Corner Radius Helper
extension UIScreen {
    var displayCornerRadius: CGFloat {
        (self.value(forKey: "_displayCornerRadius") as? CGFloat) ?? 0
    }
}

#Preview {
    AlternateTestView()
}
