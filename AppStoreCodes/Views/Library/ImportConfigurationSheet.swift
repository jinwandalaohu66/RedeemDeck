import SwiftData
import SwiftUI

struct ImportConfigurationSheet: View {
    let draft: ImportDraft
    let csvImporter: CSVImporter
    let onComplete: (CSVImportResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \AppRecord.name) private var apps: [AppRecord]
    @Query(sort: \CodeCategory.name) private var allCategories: [CodeCategory]
    @State private var selectedAppID: UUID?
    @State private var selectedCategoryID: UUID?
    @State private var productName = ""
    @State private var categoryName: String
    @State private var productID = ""
    @State private var offerReferenceName = ""
    @State private var batchName: String
    @State private var expirationDate: Date
    @State private var codeKind: CodeKind
    @State private var environment: CodeEnvironment
    @State private var platform = AppPlatform.iOS
    @State private var appVersion = ""
    @State private var isImporting = false
    @State private var errorMessage: String?

    init(
        draft: ImportDraft,
        csvImporter: CSVImporter,
        onComplete: @escaping (CSVImportResult) -> Void
    ) {
        self.draft = draft
        self.csvImporter = csvImporter
        self.onComplete = onComplete
        let filename = draft.url.deletingPathExtension().lastPathComponent
        _categoryName = State(initialValue: filename)
        _batchName = State(initialValue: filename)
        _codeKind = State(initialValue: draft.inferredKind)
        _environment = State(initialValue: draft.inferredKind == .sandbox ? .sandbox : .production)
        _expirationDate = State(initialValue: draft.suggestedExpirationDate)
    }

    private var resolvedApp: AppRecord? {
        if let selectedAppID {
            return apps.first { $0.id == selectedAppID }
        }
        guard let detectedAppStoreID = draft.detectedAppStoreID else { return nil }
        return apps.first { $0.appStoreId == detectedAppStoreID }
    }

    private var categories: [CodeCategory] {
        guard let appID = resolvedApp?.id else { return [] }
        return allCategories.filter { $0.app?.id == appID && !$0.isArchived }
    }

    private var canImport: Bool {
        guard !batchName.trimmed.isEmpty else { return false }
        if selectedCategoryID != nil { return true }
        return !productName.trimmed.isEmpty && !categoryName.trimmed.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                destinationSection
                categorySection
                batchSection
                advancedSection
            }
            .navigationTitle("Review Import")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import", action: performImport)
                        .disabled(!canImport || isImporting)
                }
            }
            .disabled(isImporting)
            .overlay { if isImporting { ProgressView("Importing") } }
            .onChange(of: selectedAppID) { _, _ in validateCategorySelection() }
            .alert(
                "Import Failed",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? String(localized: "The file could not be imported."))
            }
        }
    }

    private var destinationSection: some View {
        Section("App") {
            Picker("App", selection: $selectedAppID) {
                Text("Detect from File").tag(UUID?.none)
                ForEach(apps.filter { !$0.isArchived }) { app in
                    Text(app.name).tag(Optional(app.id))
                }
            }
        }
    }

    private var categorySection: some View {
        Section("Code Category") {
            Picker("Category", selection: $selectedCategoryID) {
                Text("Create New Category").tag(UUID?.none)
                ForEach(categories) { category in
                    Text("\(category.productName) · \(category.name)")
                        .tag(Optional(category.id))
                }
            }
            if selectedCategoryID == nil {
                TextField("Subscription or Product", text: $productName)
                TextField("Offer Name", text: $categoryName)
                DisclosureGroup("Identifiers (Optional)") {
                    TextField("Product ID", text: $productID)
                        .autocorrectionDisabled()
                    TextField("Offer Reference Name", text: $offerReferenceName)
                        .autocorrectionDisabled()
                }
            }
        }
    }

    private var batchSection: some View {
        Section {
            TextField("Batch Name", text: $batchName)
            DatePicker(
                "Expires",
                selection: $expirationDate,
                in: draft.issueDate...,
                displayedComponents: .date
            )
        } header: {
            Text("Import Batch")
        } footer: {
            Text(draft.url.lastPathComponent)
        }
    }

    private var advancedSection: some View {
        Section {
            DisclosureGroup("Advanced Options") {
                Picker("Code Type", selection: $codeKind) {
                    ForEach(CodeKind.allCases) { kind in
                        Text(kind.localizedName).tag(kind)
                    }
                }
                Picker("Environment", selection: $environment) {
                    ForEach(CodeEnvironment.allCases) { option in
                        Text(option.localizedName).tag(option)
                    }
                }
                Picker("Platform", selection: $platform) {
                    ForEach(AppPlatform.allCases) { option in
                        Text(option.localizedName).tag(option)
                    }
                }
                TextField("App Version", text: $appVersion)
            }
        }
    }

    private func validateCategorySelection() {
        guard let selectedCategoryID else { return }
        if !categories.contains(where: { $0.id == selectedCategoryID }) {
            self.selectedCategoryID = nil
        }
    }

    private func performImport() {
        isImporting = true
        let categoryInput = selectedCategoryID.map(CodeCategoryInput.existing)
            ?? CodeCategoryInput.new(
                name: categoryName.trimmed,
                productName: productName.trimmed,
                productID: productID.nilIfBlank,
                offerReferenceName: offerReferenceName.nilIfBlank
            )
        Task {
            do {
                let result = try await csvImporter.importCodes(
                    from: draft.url,
                    batchName: batchName.trimmed,
                    expirationDate: expirationDate,
                    targetAppStoreId: resolvedApp?.appStoreId,
                    codeKind: codeKind,
                    environment: codeKind == .sandbox ? .sandbox : environment,
                    platform: platform,
                    appVersion: appVersion.nilIfBlank,
                    category: categoryInput
                )
                isImporting = false
                dismiss()
                onComplete(result)
            } catch {
                isImporting = false
                errorMessage = UserFacingError.message(for: error)
            }
        }
    }
}
