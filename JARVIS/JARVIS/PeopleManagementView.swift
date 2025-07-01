import SwiftUI
import FirebaseAuth
import FirebaseFunctions
import UniformTypeIdentifiers

struct PeopleManagementView: View {
    @StateObject private var dataService = JARVISDataService.shared
    @State private var showEditSheet = false
    @State private var editPerson: Person? = nil
    @State private var showProfileSetup = false
    @State private var showVCardPicker = false
    @State private var showImportAlert = false
    @State private var importMessage = ""
    @State private var importSuccess = false
    
    var body: some View {
        VStack {
            if dataService.userProfile == nil {
                // Show profile setup if no profile exists
                ProfileSetupView()
            } else {
                // Show people list
                List {
                    ForEach(dataService.people) { person in
                        PersonRowView(person: person) {
                            editPerson = person
                            showEditSheet = true
                        }
                    }
                    .onDelete(perform: deletePerson)
                }
                .navigationTitle("People")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button("Add Person Manually") {
                                editPerson = nil
                                showEditSheet = true
                            }
                            Button("Import from vCard") {
                                showVCardPicker = true
                            }
                        } label: {
                            Label("Add", systemImage: "plus")
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { showProfileSetup = true }) {
                            Label("Profile", systemImage: "person.circle")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            PersonEditView(person: editPerson)
        }
        .sheet(isPresented: $showProfileSetup) {
            ProfileSetupView(isUpdating: true)
        }
        .fileImporter(
            isPresented: $showVCardPicker,
            allowedContentTypes: [UTType(filenameExtension: "vcf")!],
            allowsMultipleSelection: false
        ) { result in
            handleVCardImport(result: result)
        }
        .alert("Import Result", isPresented: $showImportAlert) {
            Button("OK") { }
        } message: {
            Text(importMessage)
        }
    }
    
    private func handleVCardImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            do {
                // Start accessing security-scoped resource
                let _ = url.startAccessingSecurityScopedResource()
                defer { url.stopAccessingSecurityScopedResource() }
                
                let vcardContent = try String(contentsOf: url, encoding: .utf8)
                
                // Use the existing ContactsImporter
                let importer = ContactsImporter()
                importer.importVCardFile(vcardContent: vcardContent) { success, message in
                    DispatchQueue.main.async {
                        self.importSuccess = success
                        self.importMessage = message
                        self.showImportAlert = true
                        
                        // Refresh the people list if successful
                        if success {
                            // Trigger a refresh of the data service
                            self.dataService.objectWillChange.send()
                        }
                    }
                }
            } catch {
                importSuccess = false
                importMessage = "Failed to read vCard file: \(error.localizedDescription)"
                showImportAlert = true
            }
            
        case .failure(let error):
            importSuccess = false
            importMessage = "Failed to select file: \(error.localizedDescription)"
            showImportAlert = true
        }
    }
    
    func deletePerson(at offsets: IndexSet) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        for index in offsets {
            guard index < dataService.people.count else { continue }
            let person = dataService.people[index]
            
            if let personId = person.id {
                JARVISDataService.shared.deletePerson(personId: personId, userId: userId)
            }
        }
    }
}

// MARK: - Person Row View
struct PersonRowView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let person: Person
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(person.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if !person.nicknames.isEmpty {
                        Text(person.nicknames.joined(separator: ", "))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let relationship = person.relationship, !relationship.isEmpty {
                        Text(relationship)
                            .font(.caption)
                            .foregroundColor(themeManager.currentTheme.primaryColor)
                    }
                }
                
                Spacer()
                
                if let birthday = person.birthday, !birthday.isEmpty {
                    Text(birthday)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Person Edit View (Fixed)
struct PersonEditView: View {
    let person: Person?
    @State private var name: String = ""
    @State private var nicknamesText: String = ""
    @State private var relationship: String = ""
    @State private var birthdayDate: Date = Date()
    @State private var hasBirthday: Bool = false
    @State private var notes: String = ""
    @Environment(\.dismiss) private var dismiss
    
    var isEditing: Bool { person != nil }
    
    init(person: Person?) {
        self.person = person
        _name = State(initialValue: person?.name ?? "")
        _nicknamesText = State(initialValue: person?.nicknames.joined(separator: ", ") ?? "")
        _relationship = State(initialValue: person?.relationship ?? "")
        _notes = State(initialValue: person?.notes ?? "")
        
        // Handle birthday initialization
        if let birthday = person?.birthday, !birthday.isEmpty {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            if let date = formatter.date(from: birthday) {
                _birthdayDate = State(initialValue: date)
                _hasBirthday = State(initialValue: true)
            } else {
                _birthdayDate = State(initialValue: Date())
                _hasBirthday = State(initialValue: false)
            }
        } else {
            _birthdayDate = State(initialValue: Date())
            _hasBirthday = State(initialValue: false)
        }
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Basic Information")) {
                    TextField("Full Name", text: $name)
                    TextField("Nicknames (comma separated)", text: $nicknamesText)
                    TextField("Relationship", text: $relationship)
                }
                
                Section(header: Text("Additional Details")) {
                    Toggle("Has Birthday", isOn: $hasBirthday)
                    
                    if hasBirthday {
                        DatePicker("Birthday", selection: $birthdayDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                    }
                    
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(isEditing ? "Edit Person" : "Add Person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { savePerson() }
                        .disabled(name.isEmpty)
                }
            }
        }
    }
    
    private func savePerson() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        // Parse nicknames
        let nicknames = nicknamesText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        // Format birthday
        let birthdayString: String?
        if hasBirthday {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            birthdayString = formatter.string(from: birthdayDate)
        } else {
            birthdayString = nil
        }
        
        let personToSave = Person(
            id: person?.id,
            name: name,
            nicknames: nicknames,
            relationship: relationship.isEmpty ? nil : relationship,
            birthday: birthdayString,
            notes: notes.isEmpty ? nil : notes,
            photoIds: person?.photoIds ?? [],
            iCloudContact: person?.iCloudContact,
            createdAt: person?.createdAt
        )
        
        if isEditing {
            JARVISDataService.shared.updatePerson(personToSave, userId: userId)
        } else {
            JARVISDataService.shared.addPerson(personToSave, userId: userId)
        }
        
        dismiss()
    }
}

// MARK: - Profile Setup View
struct ProfileSetupView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @StateObject private var dataService = JARVISDataService.shared
    @State private var name: String = ""
    @State private var birthdayDate: Date = Date()
    @Environment(\.dismiss) private var dismiss
    
    let isUpdating: Bool
    
    init(isUpdating: Bool = false) {
        self.isUpdating = isUpdating
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text(isUpdating ? "Update Your Profile" : "Welcome to J.A.R.V.I.S.")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top, 40)
                
                Text("Let's set up your profile so J.A.R.V.I.S. can serve you better.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                VStack(spacing: 16) {
                    TextField("Your Name", text: $name)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(40)
                        .padding(.horizontal)

                    DatePicker("Your Birthday", selection: $birthdayDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(40)
                        .padding(.horizontal)
                }
                .padding(.top, 30)
                
                Spacer()
                
                Button(action: saveProfile) {
                    Text(isUpdating ? "Update Profile" : "Complete Setup")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(themeManager.currentTheme.primaryColor)
                        .cornerRadius(40)
                        .padding(.horizontal)
                }
                .disabled(name.isEmpty)
                .padding(.bottom, 40)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isUpdating {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
        .onAppear {
            if let profile = dataService.userProfile {
                name = profile.name
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd"
                if let date = f.date(from: profile.birthday) {
                    birthdayDate = date
                }
            }
        }
    }
    
    private func saveProfile() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let birthdayString = f.string(from: birthdayDate)
        let profile = UserProfile(
            id: userId,
            name: name,
            birthday: birthdayString,
            preferences: dataService.userProfile?.preferences
        )
        
        JARVISDataService.shared.updateUserProfile(profile, userId: userId)
        
        if isUpdating {
            dismiss()
        }
    }
}

// MARK: - View Extension for Placeholder
extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}
