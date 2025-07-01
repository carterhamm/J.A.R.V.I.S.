//
//  JARVISChatView.swift
//  JARVIS
//
//  Enhanced chat interface with theme support and improved functionality
//

import SwiftUI
import UIKit
import PhotosUI
import FirebaseFunctions
import Network
import MediaPlayer
import EventKit
import MapKit
import FoundationModels
import CoreLocation
import AVFoundation

// MARK: - Enhanced Chat ViewModel with Theme Support
class JARVISChatViewModel: ObservableObject {
    @Published var messages: [JARVISMessage] = []
    @Published var messageText = ""
    @Published var selectedImages: [UIImage] = []
    @Published var showingImagePicker = false
    @Published var showingDocumentPicker = false
    @Published var isLoading = false
    @Published var keyboardHeight: CGFloat = 0
    @Published var isOffline: Bool = false
    @Published var editingMessage: JARVISMessage? = nil
    @Published var editingText: String = ""
    
    private let functions = Functions.functions()
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "ChatNetworkMonitor")
    private let eventStore = EKEventStore()
    private let locationManager = CLLocationManager()
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?
    
    private let foundationOfflineAvailable = FoundationLLM.isAvailable
    
    init() {
        print("🚀 JARVISChatView initialized - Enhanced version with Theme Support!")
        
        setupNetworkMonitoring()
        setupLocationServices()
        setupNotificationObservers()
        
        addMessage("Good evening, sir. How may I assist you today?", isUser: false)
    }
    
    private func setupLocationServices() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.startUpdatingLocation()
    }
    
    private func setupNetworkMonitoring() {
        monitor.pathUpdateHandler = { path in
            DispatchQueue.main.async {
                self.isOffline = path.status != .satisfied
                print("Chat network status: \(path.status == .satisfied ? "Online" : "Offline")")
            }
        }
        monitor.start(queue: monitorQueue)
    }
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleJarvisResponse(_:)),
            name: .jarvisResponse,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLocationRequest(_:)),
            name: .locationRequest,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }
    
    @objc private func keyboardWillShow(_ notification: Notification) {
        if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
            withAnimation(.easeOut(duration: 0.25)) {
                keyboardHeight = keyboardFrame.height
            }
        }
    }
    
    @objc private func keyboardWillHide(_ notification: Notification) {
        withAnimation(.easeOut(duration: 0.25)) {
            keyboardHeight = 0
        }
    }
    
    @objc private func handleJarvisResponse(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let message = userInfo["message"] as? String,
              let isUser = userInfo["isUser"] as? Bool else { return }
        
        DispatchQueue.main.async {
            if !self.messages.contains(where: { $0.text == message && $0.isUser == isUser }) {
                self.addMessage(message, isUser: isUser)
            }
        }
    }
    
    @objc private func handleLocationRequest(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let query = userInfo["query"] as? String else { return }
        
        DispatchQueue.main.async {
            self.handleMapQuery(query)
        }
    }
    
    func addMessage(_ text: String,
                    isUser: Bool,
                    attachments: [UIImage] = [],
                    imageUrls: [String] = [],
                    mapCoordinate: CLLocationCoordinate2D? = nil,
                    mapSpan: MKCoordinateSpan? = nil,
                    mapAnnotations: [JARVISMessage.MapAnnotation] = []) {
        let message = JARVISMessage(
            text: text,
            isUser: isUser,
            attachments: attachments,
            imageUrls: imageUrls,
            mapCoordinate: mapCoordinate,
            mapSpan: mapSpan,
            mapAnnotations: mapAnnotations
        )
        messages.append(message)
    }
    
    func editMessage(_ message: JARVISMessage, newText: String) {
        HapticManager.shared.impact(style: .light)
        
        guard let index = messages.firstIndex(where: { $0.id == message.id }) else { return }
        
        messages.removeSubrange((index + 1)...)
        
        messages[index] = JARVISMessage(
            text: newText,
            isUser: message.isUser,
            attachments: message.attachments,
            imageUrls: message.imageUrls,
            mapCoordinate: message.mapCoordinate,
            mapSpan: message.mapSpan,
            mapAnnotations: message.mapAnnotations
        )
        
        if message.isUser {
            messageText = newText
            sendMessage()
        }
    }
    
    func copyMessage(_ text: String) {
        UIPasteboard.general.string = text
        HapticManager.shared.impact(style: .light)
    }
    
    func speakMessage(_ message: JARVISMessage) {
        if let audioData = message.text.data(using: .utf8),
           let audioBase64 = getStoredAudioForMessage(message.id) {
            playAudioFromBase64(audioBase64)
        } else {
            let utterance = AVSpeechUtterance(string: message.text)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-GB")
            utterance.rate = JARVISSettings.shared.speechRate
            utterance.volume = JARVISSettings.shared.voiceVolume
            speechSynthesizer.speak(utterance)
        }
    }
    
    private func getStoredAudioForMessage(_ messageId: UUID) -> String? {
        return nil
    }
    
    private func playAudioFromBase64(_ base64String: String) {
        guard let data = base64ToData(base64String) else { return }
        
        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.volume = JARVISSettings.shared.voiceVolume
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
        } catch {
            print("Error playing audio: \(error)")
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
    
    func sendMessage() {
        guard !messageText.isEmpty || !selectedImages.isEmpty else { return }
        
        let userMessage = messageText
        addMessage(userMessage, isUser: true, attachments: selectedImages)
        
        messageText = ""
        selectedImages = []
        isLoading = true
        
        if isOffline || JARVISSettings.shared.offlineMode {
            print("Chat is offline, using local processing")
            processOffline(userMessage)
            return
        }
        
        // Enhanced message data with timezone and location info
        let messageData: [String: Any] = [
            "message": userMessage,
            "timezone": TimeZone.current.identifier,
            "location": CLLocationManager().location?.description ?? ""
        ]
        
        functions.httpsCallable("onMessage").call(messageData) { [weak self] result, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let error = error {
                    print("Firebase function error: \(error.localizedDescription)")
                    
                    if self.isOffline || JARVISSettings.shared.offlineMode {
                        self.processOffline(userMessage)
                    } else {
                        self.addMessage("I apologize, sir, but I'm having trouble connecting to my systems.", isUser: false)
                    }
                    return
                }
                
                guard let data = result?.data as? [String: Any],
                      let reply = data["text"] as? String else {
                    self.addMessage("I didn't quite catch that, sir. Could you repeat?", isUser: false)
                    return
                }
                
                let imageUrls = data["images"] as? [String] ?? []
                self.addMessage(reply, isUser: false, imageUrls: imageUrls)
                
                if let actions = data["actions"] as? [String: String] {
                    self.handleActions(actions)
                }
            }
        }
    }
    
    private func processOffline(_ text: String) {
        let lower = text.lowercased()
        
        if isTimeQuery(text) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.timeZone = TimeZone.current
            let timeString = formatter.string(from: Date())
            let timeZoneName = TimeZone.current.localizedName(for: .standard, locale: Locale.current) ?? TimeZone.current.identifier
            DispatchQueue.main.async {
                self.addMessage("The current time is \(timeString) \(timeZoneName), sir.", isUser: false)
                self.isLoading = false
            }
            return
        }
        
        if lower.contains("where is") || lower.contains("map") || lower.contains("nearest") || lower.contains("closest") || lower.contains("airport") || lower.contains("show me") {
            handleMapQuery(text)
            return
        }
        
        if lower.contains("play") || lower.contains("music") || lower.contains("song") {
            handleMusicAction(text)
            DispatchQueue.main.async {
                self.addMessage("Certainly, sir. I'll handle your music request.", isUser: false)
                self.isLoading = false
            }
            return
        }
        
        if foundationOfflineAvailable {
            Task {
                do {
                    let prompt = """
                    You are J.A.R.V.I.S., Tony Stark's AI assistant. Answer the following question in character:
                    
                    User: \(text)
                    
                    Provide a helpful, accurate response in J.A.R.V.I.S.'s characteristic British style. Keep it concise but informative.
                    """
                    
                    let assistantReply = try await FoundationLLM.respond(to: prompt)
                    
                    DispatchQueue.main.async {
                        self.addMessage(assistantReply, isUser: false)
                        self.isLoading = false
                        
                        if text.lowercased().contains("reminder") {
                            self.createReminder(text)
                        } else if text.lowercased().contains("calendar") {
                            self.createCalendarEvent(text)
                        }
                    }
                } catch {
                    print("FoundationLLM error:", error)
                    DispatchQueue.main.async {
                        self.addMessage("I apologize, sir. I'm having difficulty processing that request offline. Perhaps you could rephrase it?", isUser: false)
                        self.isLoading = false
                    }
                }
            }
        } else {
            DispatchQueue.main.async {
                self.addMessage("I'm operating in offline mode without advanced language capabilities, sir. I can still help with basic tasks like playing music, setting reminders, and checking the time.", isUser: false)
                self.isLoading = false
            }
        }
    }
    
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
    
    private func handleMapQuery(_ query: String) {
        let lower = query.lowercased()
        
        if lower.contains("nearest") || lower.contains("closest") {
            if lower.contains("airport") {
                findNearestLocation(type: .airport)
            } else if lower.contains("hospital") {
                findNearestLocation(type: .hospital)
            } else if lower.contains("restaurant") {
                findNearestLocation(type: .restaurant)
            } else if lower.contains("gas") || lower.contains("petrol") {
                findNearestLocation(type: .gasStation)
            } else {
                let searchQuery = query
                    .replacingOccurrences(of: "(?i)nearest|closest|find|show me the", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                searchNearbyPlaces(searchQuery)
            }
        } else if lower.contains("where is") || lower.contains("map of") || lower.contains("show me") {
            let searchQuery = query
                .replacingOccurrences(of: "(?i)where is|map of|show me|the map of", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            handleMapRequest(searchQuery)
        }
    }
    
    private enum LocationType {
        case airport, hospital, restaurant, gasStation
        
        var searchQuery: String {
            switch self {
            case .airport: return "airport"
            case .hospital: return "hospital"
            case .restaurant: return "restaurant"
            case .gasStation: return "gas station"
            }
        }
    }
    
    private func findNearestLocation(type: LocationType) {
        guard let userLocation = locationManager.location else {
            DispatchQueue.main.async {
                self.addMessage("I need access to your location to find the nearest \(type.searchQuery), sir.", isUser: false)
                self.isLoading = false
            }
            return
        }
        
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = type.searchQuery
        request.region = MKCoordinateRegion(
            center: userLocation.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
        
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            guard let response = response, !response.mapItems.isEmpty else {
                DispatchQueue.main.async {
                    self.addMessage("I couldn't find any \(type.searchQuery)s nearby, sir.", isUser: false)
                    self.isLoading = false
                }
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
                
                let annotations = [JARVISMessage.MapAnnotation(
                    coordinate: location.coordinate,
                    title: nearest.name ?? type.searchQuery,
                    subtitle: String(format: "%.1f miles away", distanceInMiles)
                )]
                
                DispatchQueue.main.async {
                    self.addMessage(
                        "The nearest \(type.searchQuery) is \(nearest.name ?? "unnamed"), approximately \(String(format: "%.1f", distanceInMiles)) miles away, sir.",
                        isUser: false,
                        mapCoordinate: location.coordinate,
                        mapSpan: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05),
                        mapAnnotations: annotations
                    )
                    self.isLoading = false
                }
            }
        }
    }
    
    private func searchNearbyPlaces(_ query: String) {
        guard let userLocation = locationManager.location else {
            DispatchQueue.main.async {
                self.addMessage("I need access to your location to search nearby, sir.", isUser: false)
                self.isLoading = false
            }
            return
        }
        
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(
            center: userLocation.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
        
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            guard let response = response, !response.mapItems.isEmpty else {
                DispatchQueue.main.async {
                    self.addMessage("I couldn't find any \(query) nearby, sir.", isUser: false)
                    self.isLoading = false
                }
                return
            }
            
            let annotations = response.mapItems.prefix(5).compactMap { item -> JARVISMessage.MapAnnotation? in
                guard let location = item.placemark.location else { return nil }
                let distance = location.distance(from: userLocation) / 1609.34
                return JARVISMessage.MapAnnotation(
                    coordinate: location.coordinate,
                    title: item.name ?? "Unknown",
                    subtitle: String(format: "%.1f miles", distance)
                )
            }
            
            DispatchQueue.main.async {
                self.addMessage(
                    "I found \(response.mapItems.count) \(query) locations nearby, sir. Here are the closest ones:",
                    isUser: false,
                    mapCoordinate: userLocation.coordinate,
                    mapSpan: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1),
                    mapAnnotations: Array(annotations)
                )
                self.isLoading = false
            }
        }
    }
    
    private func handleMapRequest(_ query: String) {
        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(query) { placemarks, error in
            guard let location = placemarks?.first?.location else {
                DispatchQueue.main.async {
                    self.addMessage("I couldn't find that location, sir.", isUser: false)
                    self.isLoading = false
                }
                return
            }
            
            let annotations = [JARVISMessage.MapAnnotation(
                coordinate: location.coordinate,
                title: placemarks?.first?.name ?? query,
                subtitle: placemarks?.first?.locality
            )]
            
            DispatchQueue.main.async {
                self.addMessage("Here's the location of \(query), sir.",
                                isUser: false,
                                mapCoordinate: location.coordinate,
                                mapSpan: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05),
                                mapAnnotations: annotations)
                self.isLoading = false
            }
        }
    }
    
    private func handleActions(_ actions: [String: String]) {
        if let music = actions["music"] { handleMusicAction(music) }
        if let reminder = actions["reminder"] { createReminder(reminder) }
        if let calendar = actions["calendar"] { createCalendarEvent(calendar) }
        if let maps = actions["maps"] { handleMapRequest(maps) }
    }
    
    private func handleMusicAction(_ action: String) {
        let musicPlayer = MPMusicPlayerController.systemMusicPlayer
        let lower = action.lowercased()
        
        if lower.contains("play") {
            MPMediaLibrary.requestAuthorization { status in
                if status == .authorized {
                    DispatchQueue.main.async {
                        if lower.contains("shuffle") && !lower.contains("by") {
                            let query = MPMediaQuery.songs()
                            musicPlayer.setQueue(with: query)
                            musicPlayer.shuffleMode = .songs
                            musicPlayer.play()
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
                                            musicPlayer.setQueue(with: collection)
                                            musicPlayer.play()
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
                                        musicPlayer.setQueue(with: collection)
                                        musicPlayer.shuffleMode = .songs
                                        musicPlayer.play()
                                        found = true
                                    }
                                }
                                
                                if !found {
                                    let query = MPMediaQuery.songs()
                                    musicPlayer.setQueue(with: query)
                                    musicPlayer.shuffleMode = .songs
                                    musicPlayer.play()
                                }
                            } else {
                                musicPlayer.play()
                            }
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self.addMessage("I need permission to access your music library, sir.", isUser: false)
                    }
                }
            }
        } else if lower.contains("pause") {
            musicPlayer.pause()
        } else if lower.contains("next") || lower.contains("skip") {
            musicPlayer.skipToNextItem()
        } else if lower.contains("previous") || lower.contains("back") {
            musicPlayer.skipToPreviousItem()
        } else if lower.contains("stop") {
            musicPlayer.stop()
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
    
    private func createReminder(_ reminderText: String) {
        eventStore.requestAccess(to: .reminder) { granted, error in
            guard granted else { return }
            
            let reminder = EKReminder(eventStore: self.eventStore)
            reminder.title = reminderText
            reminder.calendar = self.eventStore.defaultCalendarForNewReminders()
            
            if reminderText.lowercased().contains("tomorrow") {
                reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: Date().addingTimeInterval(86400))
            } else if reminderText.lowercased().contains("today") {
                reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            }
            
            do {
                try self.eventStore.save(reminder, commit: true)
            } catch {
                print("Failed to create reminder: \(error)")
            }
        }
    }
    
    private func createCalendarEvent(_ eventInfo: String) {
        eventStore.requestAccess(to: .event) { granted, error in
            guard granted else { return }
            
            let event = EKEvent(eventStore: self.eventStore)
            let components = eventInfo.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            event.title = components.first ?? "Event"
            
            if components.count > 1 {
                if components[1].lowercased().contains("tomorrow") {
                    event.startDate = Date().addingTimeInterval(86400)
                } else if components[1].lowercased().contains("today") {
                    event.startDate = Date()
                } else {
                    event.startDate = Date()
                }
            } else {
                event.startDate = Date()
            }
            
            event.endDate = event.startDate.addingTimeInterval(3600)
            event.calendar = self.eventStore.defaultCalendarForNewEvents
            
            do {
                try self.eventStore.save(event, span: .thisEvent)
            } catch {
                print("Failed to save event: \(error)")
            }
        }
    }
    
    var canSend: Bool {
        !messageText.isEmpty || !selectedImages.isEmpty
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        monitor.cancel()
    }
}

// MARK: - Message Model
struct JARVISMessage: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
    let timestamp = Date()
    var attachments: [UIImage] = []
    var imageUrls: [String] = []
    var mapCoordinate: CLLocationCoordinate2D? = nil
    var mapSpan: MKCoordinateSpan? = nil
    var mapAnnotations: [MapAnnotation] = []
    
    struct MapAnnotation: Identifiable {
        let id = UUID()
        let coordinate: CLLocationCoordinate2D
        let title: String
        let subtitle: String?
    }
}

// MARK: - Enhanced Message Bubble with Theme Support
struct JARVISMessageBubble: View {
    let message: JARVISMessage
    @StateObject private var viewModel: JARVISChatViewModel
    @State private var selectedImageUrl: String? = nil
    @State private var showingFullScreenImage = false
    @State private var showingEditSheet = false
    @State private var editText = ""
    @EnvironmentObject var themeManager: ThemeManager
    
    init(message: JARVISMessage, viewModel: JARVISChatViewModel) {
        self.message = message
        self._viewModel = StateObject(wrappedValue: viewModel)
    }
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.isUser { Spacer(minLength: 50) }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                // Show attached images
                if !message.attachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(message.attachments.enumerated()), id: \.offset) { _, image in
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 150, height: 150)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                    .frame(maxWidth: 250)
                }
                
                // Show images from URLs
                if !message.imageUrls.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(message.imageUrls, id: \.self) { imageUrl in
                                AsyncImage(url: URL(string: imageUrl)) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 150, height: 150)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                            .onTapGesture {
                                                selectedImageUrl = imageUrl
                                                showingFullScreenImage = true
                                            }
                                    case .failure:
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.gray.opacity(0.3))
                                            .frame(width: 150, height: 150)
                                            .overlay(
                                                Image(systemName: "photo")
                                                    .foregroundColor(.gray)
                                            )
                                    case .empty:
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.gray.opacity(0.3))
                                            .frame(width: 150, height: 150)
                                            .overlay(
                                                ProgressView()
                                            )
                                    @unknown default:
                                        EmptyView()
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: 250)
                }

                // Map view
                if let coord = message.mapCoordinate {
                    MessageMapView(
                        coordinate: coord,
                        span: message.mapSpan ?? MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05),
                        annotations: message.mapAnnotations
                    )
                }
                
                // Message text
                if !message.text.isEmpty {
                    Text(message.text)
                        .fontWeight(message.isUser ? .semibold : .regular)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 20)
                        .background(
                            Group {
                                if !message.isUser {
                                    RoundedRectangle(cornerRadius: 32)
                                        .fill(Color.clear)
                                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 32))
                                } else {
                                    RoundedRectangle(cornerRadius: 32)
                                        .fill(themeManager.currentTheme.primaryColor)
                                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 32))
                                }
                            }
                        )
                        .foregroundColor(.white)
                        .textSelection(.disabled)
                }
                
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.gray.opacity(0.6))
                    .padding(.horizontal, 4)
            }
            
            if !message.isUser { Spacer(minLength: 50) }
        }
        .contentShape(RoundedRectangle(cornerRadius: 32))
        .contextMenu {
            Button {
                viewModel.copyMessage(message.text)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            if message.isUser {
                Button {
                    editText = message.text
                    showingEditSheet = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            } else {
                Button {
                    viewModel.speakMessage(message)
                } label: {
                    Label("Speak", systemImage: "speaker.wave.2")
                }
            }
        }
        .onLongPressGesture(minimumDuration: 0.1) {
            HapticManager.shared.impact(style: .light)
        }
        .padding(.horizontal, 12)
        .fullScreenCover(isPresented: $showingFullScreenImage) {
            if let imageUrl = selectedImageUrl {
                FullScreenImageView(imageUrl: imageUrl, isPresented: $showingFullScreenImage)
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            EditMessageSheet(
                originalText: message.text,
                editText: $editText,
                isPresented: $showingEditSheet
            ) {
                viewModel.editMessage(message, newText: editText)
            }
        }
    }
}

// MARK: - Enhanced Chat View with Theme Support
struct JARVISChatView: View {
    @State private var isFullScreen = false
    @State private var gradientPhase: CGFloat = 0
    @StateObject private var viewModel = JARVISChatViewModel()
    @Namespace var bottomID
    @EnvironmentObject var themeManager: ThemeManager

    private let gradientTimer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 12) {
                                ForEach(viewModel.messages) { message in
                                    JARVISMessageBubble(message: message, viewModel: viewModel)
                                        .environmentObject(themeManager)
                                        .id(message.id)
                                }
                                
                                if viewModel.isLoading {
                                    HStack {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                            .progressViewStyle(CircularProgressViewStyle(tint: themeManager.currentTheme.primaryColor))
                                        Text("Thinking...")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                    .padding()
                                }
                                
                                Color.clear
                                    .frame(height: 1)
                                    .id(bottomID)
                            }
                            .padding(.vertical)
                        }
                        .onChange(of: viewModel.messages.count) { _ in
                            withAnimation {
                                proxy.scrollTo(bottomID, anchor: .bottom)
                            }
                        }
                        .onAppear {
                            proxy.scrollTo(bottomID, anchor: .bottom)
                        }
                    }
                    .padding(.top, isFullScreen ? 55 : 8)
                    
                    // Input area with theme support
                    VStack(spacing: 8) {
                        if !viewModel.selectedImages.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(Array(viewModel.selectedImages.enumerated()), id: \.offset) { index, image in
                                        ZStack(alignment: .topTrailing) {
                                            Image(uiImage: image)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 60, height: 60)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                            
                                            Button {
                                                viewModel.selectedImages.remove(at: index)
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundColor(.white)
                                                    .background(Color.black.opacity(0.6))
                                                    .clipShape(Circle())
                                            }
                                            .offset(x: 5, y: -5)
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                            .frame(height: 70)
                        }
                        
                        // Enhanced input field with theme
                        HStack(spacing: 12) {
                            Menu {
                                Button {
                                    viewModel.showingImagePicker = true
                                } label: {
                                    Label("Photo Library", systemImage: "photo")
                                }
                                
                                Button {
                                    viewModel.showingDocumentPicker = true
                                } label: {
                                    Label("Files", systemImage: "doc")
                                }
                            } label: {
                                Image(systemName: "paperclip")
                                    .font(.system(size: 22))
                                    .foregroundStyle(themeManager.currentTheme.primaryColor)
                            }
                            .padding(.leading, 5)

                            TextField("Message J.A.R.V.I.S.", text: $viewModel.messageText)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .textFieldStyle(PlainTextFieldStyle())
                                .onSubmit {
                                    viewModel.sendMessage()
                                }

                            Button {
                                viewModel.sendMessage()
                            } label: {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(
                                        viewModel.canSend
                                        ? themeManager.currentTheme.primaryColor
                                        : Color.gray.opacity(0.5)
                                    )
                            }
                            .disabled(!viewModel.canSend)
                            .padding(.trailing, 5)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 80)
                                .fill(Color.clear)
                                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 80))
                        )
                        .overlay(
                            ZStack {
                                RoundedRectangle(cornerRadius: 80)
                                    .stroke(glowGradient, lineWidth: 6)
                                    .blur(radius: 8)
                                RoundedRectangle(cornerRadius: 80)
                                    .stroke(glowGradient, lineWidth: 0.5)
                            }
                        )
                    }
                    .padding(.bottom, isFullScreen && viewModel.keyboardHeight == 0 ? 25 : 16)
                    .padding(.horizontal, 12)
                    .offset(y: isFullScreen
                                ? (viewModel.keyboardHeight > 0
                                    ? geo.size.height * 0.05
                                    : -15)
                                : 0)
                }
                .frame(
                    width: isFullScreen ? geo.size.width : geo.size.width * 0.9,
                    height: isFullScreen
                        ? (geo.size.height - viewModel.keyboardHeight)
                    : min(geo.size.height * 0.7, geo.size.height - viewModel.keyboardHeight - 100)
                )
                .background(
                    ZStack(alignment: .top) {
                        RoundedRectangle(cornerRadius: isFullScreen ? 0 : 30)
                            .fill(Color.clear)
                            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: isFullScreen ? 0 : 30))
                            .frame(height: isFullScreen
                                        ? (viewModel.keyboardHeight > 0
                                            ? geo.size.height - viewModel.keyboardHeight + geo.size.height * 0.05 + 20
                                            : geo.size.height)
                                        : nil)
                    }
                    .offset(y: isFullScreen && viewModel.keyboardHeight > 0 ? 20 : 0)
                )
                .position(
                    x: geo.size.width / 2,
                    y: isFullScreen
                        ? (geo.size.height - viewModel.keyboardHeight) / 2
                    : geo.size.height / 2 - (viewModel.keyboardHeight * 0.3)
                )
                .onTapGesture {
                    withAnimation(.spring()) {
                        isFullScreen.toggle()
                    }
                    HapticManager.shared.impact(style: .medium)
                }
                .animation(.spring(), value: isFullScreen)
                .animation(.easeOut(duration: 0.25), value: viewModel.keyboardHeight)
            }
        }
        .ignoresSafeArea(.container, edges: isFullScreen ? .all : [])
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onReceive(gradientTimer) { _ in
            withAnimation(.linear(duration: 0.2)) {
                gradientPhase = (gradientPhase + 0.05).truncatingRemainder(dividingBy: 1.0)
            }
        }
        .sheet(isPresented: $viewModel.showingImagePicker) {
            JARVISImagePicker(selectedImages: $viewModel.selectedImages)
        }
        .sheet(isPresented: $viewModel.showingDocumentPicker) {
            JARVISDocumentPicker(selectedImages: $viewModel.selectedImages)
        }
    }
    
    private var glowGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: themeManager.currentTheme.secondaryColor, location: 0.0 + gradientPhase),
                .init(color: themeManager.currentTheme.primaryColor, location: 0.5 + gradientPhase),
                .init(color: themeManager.currentTheme.secondaryColor, location: 1.0 + gradientPhase)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Supporting Views
struct MessageMapView: View {
    let coordinate: CLLocationCoordinate2D
    let span: MKCoordinateSpan
    let annotations: [JARVISMessage.MapAnnotation]
    
    @State private var region: MKCoordinateRegion
    
    init(coordinate: CLLocationCoordinate2D, span: MKCoordinateSpan, annotations: [JARVISMessage.MapAnnotation]) {
        self.coordinate = coordinate
        self.span = span
        self.annotations = annotations
        self._region = State(initialValue: MKCoordinateRegion(center: coordinate, span: span))
    }
    
    var body: some View {
        Map(coordinateRegion: $region, annotationItems: annotations) { annotation in
            MapAnnotation(coordinate: annotation.coordinate) {
                VStack {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundColor(.red)
                        .font(.title)
                    
                    VStack(alignment: .center, spacing: 2) {
                        Text(annotation.title)
                            .font(.caption)
                            .fontWeight(.bold)
                        if let subtitle = annotation.subtitle {
                            Text(subtitle)
                                .font(.caption2)
                        }
                    }
                    .padding(4)
                    .background(Color.white.opacity(0.9))
                    .cornerRadius(6)
                }
            }
        }
        .frame(width: 300, height: 200)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
}

struct FullScreenImageView: View {
    let imageUrl: String
    @Binding var isPresented: Bool
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            AsyncImage(url: URL(string: imageUrl)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                case .failure:
                    Image(systemName: "photo")
                        .foregroundColor(.gray)
                case .empty:
                    ProgressView()
                @unknown default:
                    EmptyView()
                }
            }
            
            VStack {
                HStack {
                    Spacer()
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .padding()
                }
                Spacer()
            }
        }
    }
}

struct EditMessageSheet: View {
    let originalText: String
    @Binding var editText: String
    @Binding var isPresented: Bool
    let onSave: () -> Void
    
    var body: some View {
        NavigationView {
            VStack {
                Text("Edit Message")
                    .font(.headline)
                    .padding()
                
                TextEditor(text: $editText)
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    .padding()
                
                Spacer()
            }
            .navigationBarItems(
                leading: Button("Cancel") {
                    isPresented = false
                },
                trailing: Button("Save") {
                    onSave()
                    isPresented = false
                }
                .disabled(editText.isEmpty)
            )
        }
    }
}

struct JARVISImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImages: [UIImage]
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 0
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: JARVISImagePicker
        
        init(_ parent: JARVISImagePicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            
            for result in results {
                if result.itemProvider.canLoadObject(ofClass: UIImage.self) {
                    result.itemProvider.loadObject(ofClass: UIImage.self) { image, error in
                        if let image = image as? UIImage {
                            DispatchQueue.main.async {
                                self.parent.selectedImages.append(image)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct JARVISDocumentPicker: UIViewControllerRepresentable {
    @Binding var selectedImages: [UIImage]
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.image, .pdf, .text])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = true
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: JARVISDocumentPicker
        
        init(_ parent: JARVISDocumentPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            for url in urls {
                if let image = UIImage(contentsOfFile: url.path) {
                    DispatchQueue.main.async {
                        self.parent.selectedImages.append(image)
                    }
                }
            }
        }
    }
}

#Preview {
    JARVISChatView()
        .environmentObject(ThemeManager.shared)
}
