import SwiftData
import SwiftUI

struct AppEditorSheet: View {
    let app: AppRecord?
    let onSave: ((Bool) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSession.self) private var session
    @Environment(AppFeedbackCenter.self) private var feedback
    @State private var name: String
    @State private var appStoreID: String
    @State private var bundleID: String
    @State private var notes: String
    @State private var fetchedMetadata: AppStoreMetadata?
    @State private var isLookingUp = false
    @State private var errorMessage: String?
    @State private var errorTitle = String(localized: "App Store Lookup Failed")

    init(app: AppRecord? = nil, onSave: ((Bool) -> Void)? = nil) {
        self.app = app
        self.onSave = onSave
        _name = State(initialValue: app?.name ?? "")
        _appStoreID = State(initialValue: app?.appStoreId ?? "")
        _bundleID = State(initialValue: app?.bundleId ?? "")
        _notes = State(initialValue: app?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                if fetchedMetadata?.artworkURL != nil || app?.iconURL != nil {
                    Section {
                        HStack {
                            Spacer()
                            AppArtworkView(
                                iconURL: fetchedMetadata?.artworkURL ?? app?.iconURL,
                                size: 72
                            )
                            Spacer()
                        }
                    }
                }
                Section("App") {
                    TextField("Name", text: $name)
                    TextField("App Store ID", text: $appStoreID)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    Button("Fill from App Store") {
                        lookupMetadata()
                    }
                    .disabled(appStoreID.trimmed.isEmpty || isLookingUp)
                    TextField("Bundle ID", text: $bundleID)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                }
                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle(app == nil ? "Add App" : "Edit App")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmed.isEmpty || appStoreID.trimmed.isEmpty || isLookingUp)
                }
            }
            .disabled(isLookingUp)
            .overlay {
                if isLookingUp {
                    ProgressView("Looking Up App")
                }
            }
            .alert(
                errorTitle,
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? String(localized: "The app information could not be loaded."))
            }
        }
        .appFeedbackPresenter()
    }

    private func lookupMetadata() {
        errorTitle = String(localized: "App Store Lookup Failed")
        isLookingUp = true
        Task {
            do {
                let metadata = try await AppStoreLookupService.shared.lookupApp(byID: appStoreID)
                fetchedMetadata = metadata
                name = metadata.name
                bundleID = metadata.bundleID
                feedback.show(String(localized: "App Store information loaded."), tone: .information)
            } catch {
                errorMessage = UserFacingError.message(for: error)
            }
            isLookingUp = false
        }
    }

    private func save() {
        let record = app ?? AppRecord(name: name.trimmed, appStoreId: appStoreID.trimmed)
        record.name = name.trimmed
        record.appStoreId = appStoreID.trimmed
        record.bundleId = bundleID.nilIfBlank
        record.notes = notes.nilIfBlank
        if let metadata = fetchedMetadata {
            record.iconURL = metadata.artworkURL
            record.appStoreURL = metadata.appStoreURL
            record.metadataLastUpdated = Date()
        }
        if app == nil {
            modelContext.insert(record)
        }
        do {
            try modelContext.save()
            session.dataDidChange()
            onSave?(app == nil)
            dismiss()
        } catch {
            modelContext.rollback()
            errorTitle = String(localized: "Unable to Save")
            errorMessage = UserFacingError.message(for: error)
        }
    }
}
