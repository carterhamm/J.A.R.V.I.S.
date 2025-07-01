import Foundation
import FirebaseFirestore
import FirebaseFunctions
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}

class ChatViewModel: ObservableObject {
  private lazy var functions = Functions.functions()

  func send(_ text: String) {
    functions.httpsCallable("onMessage")
      .call(["message": text]) { result, error in
        if let error = error {
          print("Error:", error.localizedDescription)
          return
        }
        guard let data = result?.data as? [String:Any] else { return }

        // Text reply
        if let reply = data["text"] as? String {
          DispatchQueue.main.async {
            // append to your UI chat messages
          }
        }
        // Images
        if let images = data["images"] as? [String] {
          // show a carousel of AsyncImage(url: URL(string: imageURL))
        }
        // Music commands
        if let musicCmd = data["musicCommand"] as? [String:Any] {
          // call your MusicKit helper
        }
      }
  }
}

// MARK: - User Profile Model
struct UserProfile: Identifiable {
    var id: String?            // The document ID (same as user's UID)
    var name: String           // User's name
    var birthday: String       // User's birthday in YYYY-MM-DD format
    var preferences: [String: Any]? // Additional preferences
    
    init(id: String? = nil, name: String, birthday: String, preferences: [String: Any]? = nil) {
        self.id = id
        self.name = name
        self.birthday = birthday
        self.preferences = preferences
    }
    
    init?(from data: [String: Any]) {
        guard let name = data["name"] as? String,
              let birthday = data["birthday"] as? String else { return nil }
        
        self.name = name
        self.birthday = birthday
        self.preferences = data["preferences"] as? [String: Any]
    }
    
    var firestoreData: [String: Any] {
        var data: [String: Any] = [
            "name": name,
            "birthday": birthday
        ]
        if let preferences = preferences {
            data["preferences"] = preferences
        }
        return data
    }
}

// MARK: - Person Model (known contacts)
struct Person: Identifiable {
    var id: String?            // Firestore document ID
    var name: String           // Full name of the person
    var nicknames: [String]    // Array of nicknames
    var relationship: String?  // Relationship (e.g. "Friend", "Family")
    var birthday: String?      // Birthday in YYYY-MM-DD format
    var notes: String?         // Additional notes
    var photoIds: [String]     // IDs of associated photos
    var iCloudContact: String? // Link to iCloud contact
    var createdAt: Date?       // When the contact was created
    
    init(id: String? = nil, name: String, nicknames: [String] = [],
         relationship: String? = nil, birthday: String? = nil,
         notes: String? = nil, photoIds: [String] = [],
         iCloudContact: String? = nil, createdAt: Date? = nil) {
        self.id = id
        self.name = name
        self.nicknames = nicknames
        self.relationship = relationship
        self.birthday = birthday
        self.notes = notes
        self.photoIds = photoIds
        self.iCloudContact = iCloudContact
        self.createdAt = createdAt
    }
}

// MARK: - Memory Model
struct Memory: Identifiable {
    var id: String?
    var type: String           // Type of memory (e.g., "event", "note", "milestone")
    var date: Date
    var description: String
    var peopleInvolved: [String]
    var photos: [String]
}

// MARK: - Conversation Model
struct ConversationEntry: Identifiable {
    var id: String?
    var sender: String         // "user" or "assistant"
    var text: String
    var timestamp: Date
}

// MARK: - Reminder Model
struct Reminder: Identifiable {
    var id: String?
    var title: String
    var dueDate: Date
    var notes: String?
    var isCompleted: Bool = false
}

// MARK: - Note Model
struct Note: Identifiable {
    var id: String?
    var title: String
    var content: String
    var createdAt: Date
    var updatedAt: Date
}

// MARK: - Event Model
struct Event: Identifiable {
    var id: String?
    var title: String
    var startDate: Date
    var endDate: Date?
    var location: String?
    var notes: String?
    var attendees: [String]
}

// MARK: - Person/Contact Extensions
extension Person {
    var firestoreData: [String: Any] {
        var data: [String: Any] = [
            "name": name,
            "nicknames": nicknames,
            "photoIds": photoIds,
            "createdAt": createdAt ?? Date()
        ]
        
        if let relationship = relationship {
            data["relationship"] = relationship
        }
        if let birthday = birthday {
            data["birthday"] = birthday
        }
        if let notes = notes {
            data["notes"] = notes
        }
        if let iCloudContact = iCloudContact {
            data["iCloudContact"] = iCloudContact
        }
        
        return data
    }
    
    init?(from document: DocumentSnapshot) {
        guard let data = document.data(),
              let name = data["name"] as? String else { return nil }
        
        self.id = document.documentID
        self.name = name
        self.nicknames = data["nicknames"] as? [String] ?? []
        self.relationship = data["relationship"] as? String
        self.birthday = data["birthday"] as? String
        self.notes = data["notes"] as? String
        self.photoIds = data["photoIds"] as? [String] ?? []
        self.iCloudContact = data["iCloudContact"] as? String
        
        if let timestamp = data["createdAt"] as? Timestamp {
            self.createdAt = timestamp.dateValue()
        } else {
            self.createdAt = nil
        }
    }
}
