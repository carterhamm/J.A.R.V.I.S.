import Foundation
import FirebaseFirestore
import FirebaseAuth
import Photos
import Combine
import UIKit

class JARVISDataService: ObservableObject {
    static let shared = JARVISDataService()
    private let db = Firestore.firestore()
    
    @Published var userProfile: UserProfile?
    @Published var people: [Person] = []
    @Published var memories: [Memory] = []
    
    private var listeners: [ListenerRegistration] = []
    
    private init() {
        setupAuthListener()
    }
    
    deinit {
        listeners.forEach { $0.remove() }
    }
    
    // MARK: - Auth Listener
    private func setupAuthListener() {
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            if let userId = user?.uid {
                self?.startListening(userId: userId)
            } else {
                self?.stopListening()
            }
        }
    }
    
    private func startListening(userId: String) {
        stopListening()
        loadUserProfile(userId: userId)
        listenToPeople(userId: userId)
        listenToMemories(userId: userId)
    }
    
    private func stopListening() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
        userProfile = nil
        people = []
        memories = []
    }
    
    // MARK: - User Profile Management
    func loadUserProfile(userId: String) {
        let listener = db.collection("users").document(userId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let data = snapshot?.data() else { return }
                
                // Check if we have name and birthday as direct fields (matching your schema)
                if let name = data["name"] as? String,
                   let birthday = data["birthday"] as? String {
                    self?.userProfile = UserProfile(
                        id: userId,
                        name: name,
                        birthday: birthday,
                        preferences: data["preferences"] as? [String: Any]
                    )
                } else {
                    // Create default profile if none exists
                    self?.createDefaultProfile(userId: userId)
                }
            }
        
        listeners.append(listener)
    }
    
    func createDefaultProfile(userId: String) {
        let defaultProfile = UserProfile(
            name: "User",
            birthday: "2005-03-23",
            preferences: ["theme": "dark", "notifications": "true"]
        )
        
        updateUserProfile(defaultProfile, userId: userId)
    }
    
    func updateUserProfile(_ profile: UserProfile, userId: String) {
        // Store name and birthday as direct fields to match your schema
        var data: [String: Any] = [
            "name": profile.name,
            "birthday": profile.birthday
        ]
        
        if let preferences = profile.preferences {
            data["preferences"] = preferences
        }
        
        db.collection("users").document(userId).setData(data, merge: true) { [weak self] error in
            if error == nil {
                self?.userProfile = profile
            }
        }
    }
    
    // MARK: - People Management (Updated to match your schema)
    private func listenToPeople(userId: String) {
        // Updated path to match your schema: /people/{userId}/contacts
        let listener = db.collection("people").document(userId).collection("contacts")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let documents = snapshot?.documents else { return }
                
                self?.people = documents.compactMap { Person(from: $0) }
                    .sorted { $0.name < $1.name }
            }
        
        listeners.append(listener)
    }
    
    func addPerson(_ person: Person, userId: String) {
        db.collection("people").document(userId).collection("contacts")
            .addDocument(data: person.firestoreData)
    }
    
    func updatePerson(_ person: Person, userId: String) {
        guard let personId = person.id else { return }
        
        db.collection("people").document(userId).collection("contacts")
            .document(personId).updateData(person.firestoreData)
    }
    
    func deletePerson(personId: String, userId: String) {
        db.collection("people").document(userId).collection("contacts")
            .document(personId).delete()
    }
    
    func findPersonByNameOrNickname(_ query: String) -> Person? {
        let lowercased = query.lowercased()
        return people.first { person in
            person.name.lowercased().contains(lowercased) ||
            person.nicknames.contains { $0.lowercased().contains(lowercased) }
        }
    }
    
    // MARK: - Memory Management
    private func listenToMemories(userId: String) {
        let listener = db.collection("memories").document(userId).collection("items")
            .order(by: "date", descending: true)
            .limit(to: 50)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let documents = snapshot?.documents else { return }
                
                self?.memories = documents.compactMap { doc -> Memory? in
                    let data = doc.data()
                    guard let type = data["type"] as? String,
                          let timestamp = data["date"] as? Timestamp,
                          let description = data["description"] as? String else { return nil }
                    
                    return Memory(
                        id: doc.documentID,
                        type: type,
                        date: timestamp.dateValue(),
                        description: description,
                        peopleInvolved: data["peopleInvolved"] as? [String] ?? [],
                        photos: data["photos"] as? [String] ?? []
                    )
                }
            }
        
        listeners.append(listener)
    }
    
    func addMemory(_ memory: Memory, userId: String) {
        db.collection("memories").document(userId).collection("items")
            .addDocument(data: [
                "type": memory.type,
                "date": Timestamp(date: memory.date),
                "description": memory.description,
                "peopleInvolved": memory.peopleInvolved,
                "photos": memory.photos
            ])
    }
    
    // MARK: - Conversation Storage
    func storeConversation(userMessage: String, assistantResponse: String, userId: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        
        let userMessageData: [String: Any] = [
            "role": "user",
            "content": userMessage,
            "timestamp": timestamp
        ]
        
        let assistantMessageData: [String: Any] = [
            "role": "assistant",
            "content": assistantResponse,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        let conversationData: [String: Any] = [
            "timestamp": FieldValue.serverTimestamp(),
            "messages": [userMessageData, assistantMessageData]
        ]
        
        // Store in user's conversation subcollection
        db.collection("users").document(userId).collection("conversations")
            .addDocument(data: conversationData)
        
        // Also update main conversation thread - arrayUnion expects array elements
        db.collection("conversations").document(userId).setData([
            "messages": FieldValue.arrayUnion([userMessageData, assistantMessageData]),
            "lastUpdated": FieldValue.serverTimestamp()
        ], merge: true)
    }
    
    // MARK: - Context for J.A.R.V.I.S.
    func getContextForJARVIS(completion: @escaping (String) -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion("")
            return
        }
        
        var context = ""
        
        // Add user profile
        if let profile = userProfile {
            context += "USER PROFILE:\n"
            context += "Name: \(profile.name)\n"
            context += "Birthday: \(profile.birthday)\n"
            
            if let preferences = profile.preferences {
                context += "Preferences: \(preferences)\n"
            }
            context += "\n"
        }
        
        // Add current date and time
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        formatter.timeZone = TimeZone.current
        context += "CURRENT DATE/TIME: \(formatter.string(from: Date()))\n"
        context += "TIMEZONE: \(TimeZone.current.identifier)\n\n"
        
        // Add people database
        if !people.isEmpty {
            context += "PEOPLE YOU KNOW:\n"
            for person in people {
                context += "- \(person.name)"
                if !person.nicknames.isEmpty {
                    context += " (nicknames: \(person.nicknames.joined(separator: ", ")))"
                }
                if let relationship = person.relationship, !relationship.isEmpty {
                    context += " - \(relationship)"
                }
                if let birthday = person.birthday, !birthday.isEmpty {
                    context += " - Birthday: \(birthday)"
                }
                if let notes = person.notes, !notes.isEmpty {
                    context += " - Notes: \(notes)"
                }
                context += "\n"
            }
            context += "\n"
        }
        
        // Add recent memories
        if !memories.isEmpty {
            context += "RECENT MEMORIES:\n"
            for memory in memories.prefix(5) {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                context += "- \(formatter.string(from: memory.date)): \(memory.description)\n"
            }
            context += "\n"
        }
        
        // Get recent conversations
        db.collection("users").document(userId).collection("conversations")
            .order(by: "timestamp", descending: true)
            .limit(to: 5)
            .getDocuments { snapshot, error in
                if let documents = snapshot?.documents {
                    context += "RECENT CONVERSATIONS:\n"
                    for doc in documents {
                        if let messages = doc.data()["messages"] as? [[String: Any]] {
                            for message in messages.prefix(1) { // Just the user's message
                                if let role = message["role"] as? String,
                                   role == "user",
                                   let content = message["content"] as? String {
                                    context += "- \(content.prefix(50))...\n"
                                }
                            }
                        }
                    }
                }
                
                completion(context)
            }
    }
    
    // MARK: - Photo Search
    func searchPhotosForPerson(_ person: Person, completion: @escaping ([PHAsset]) -> Void) {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else {
                completion([])
                return
            }
            
            DispatchQueue.global(qos: .userInitiated).async {
                var allAssets: [PHAsset] = []
                
                // Search for albums matching person's name or nicknames
                let searchTerms = [person.name] + person.nicknames
                
                for term in searchTerms {
                    // Search albums
                    let albumOptions = PHFetchOptions()
                    albumOptions.predicate = NSPredicate(format: "localizedTitle CONTAINS[c] %@", term)
                    
                    let albums = PHAssetCollection.fetchAssetCollections(
                        with: .album,
                        subtype: .any,
                        options: albumOptions
                    )
                    
                    albums.enumerateObjects { collection, _, _ in
                        let assetOptions = PHFetchOptions()
                        assetOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                        
                        let assets = PHAsset.fetchAssets(in: collection, options: assetOptions)
                        assets.enumerateObjects { asset, _, _ in
                            if !allAssets.contains(asset) {
                                allAssets.append(asset)
                            }
                        }
                    }
                    
                    // Also search for photos with the term in their title
                    let assetOptions = PHFetchOptions()
                    assetOptions.predicate = NSPredicate(format: "title CONTAINS[c] %@", term)
                    
                    let titleAssets = PHAsset.fetchAssets(with: .image, options: assetOptions)
                    titleAssets.enumerateObjects { asset, _, _ in
                        if !allAssets.contains(asset) {
                            allAssets.append(asset)
                        }
                    }
                }
                
                DispatchQueue.main.async {
                    completion(Array(allAssets.prefix(20))) // Limit to 20 photos
                }
            }
        }
    }
    
    // MARK: - Helper to get images from PHAssets
    func getImagesFromAssets(_ assets: [PHAsset], targetSize: CGSize = CGSize(width: 300, height: 300), completion: @escaping ([UIImage]) -> Void) {
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        
        var images: [UIImage] = []
        let dispatchGroup = DispatchGroup()
        
        for asset in assets {
            dispatchGroup.enter()
            
            manager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { image, _ in
                if let image = image {
                    images.append(image)
                }
                dispatchGroup.leave()
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            completion(images)
        }
    }
}
