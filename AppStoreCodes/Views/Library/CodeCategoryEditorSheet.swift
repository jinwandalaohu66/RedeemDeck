import SwiftUI

struct CodeCategoryEditorSheet: View {
    let app: AppSummary
    let category: CodeCategorySummary?
    let repository: CodeVaultRepository
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var productName: String
    @State private var categoryName: String
    @State private var productID: String
    @State private var offerReferenceName: String
    @State private var notes: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        app: AppSummary,
        category: CodeCategorySummary? = nil,
        repository: CodeVaultRepository,
        onSave: @escaping () -> Void = {}
    ) {
        self.app = app
        self.category = category
        self.repository = repository
        self.onSave = onSave
        _productName = State(initialValue: category?.productName ?? "")
        _categoryName = State(initialValue: category?.name ?? "")
        _productID = State(initialValue: category?.productID ?? "")
        _offerReferenceName = State(initialValue: category?.offerReferenceName ?? "")
        _notes = State(initialValue: category?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Product") {
                    TextField("Subscription or Product", text: $productName)
                    TextField("Product ID (Optional)", text: $productID)
                        .autocorrectionDisabled()
                }
                Section {
                    TextField("Offer Name", text: $categoryName)
                    TextField("Offer Reference Name (Optional)", text: $offerReferenceName)
                        .autocorrectionDisabled()
                    TextField("Notes (Optional)", text: $notes, axis: .vertical)
                } header: {
                    Text("Offer")
                } footer: {
                    Text("Examples: Free for 1 Month, 50% Off for 3 Months, or Standard Price.")
                }
            }
            .navigationTitle(category == nil ? "Add Code Category" : "Edit Code Category")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave || isSaving)
                }
            }
            .disabled(isSaving)
            .overlay { if isSaving { ProgressView() } }
            .alert(
                "Unable to Save",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? String(localized: "The code category could not be saved."))
            }
        }
    }

    private var canSave: Bool {
        !productName.trimmed.isEmpty && !categoryName.trimmed.isEmpty
    }

    private func save() {
        isSaving = true
        let request = CodeCategorySaveRequest(
            id: category?.id,
            appID: app.id,
            name: categoryName.trimmed,
            productName: productName.trimmed,
            productID: productID.nilIfBlank,
            offerReferenceName: offerReferenceName.nilIfBlank,
            notes: notes.nilIfBlank
        )
        Task {
            do {
                try await repository.saveCodeCategory(request)
                onSave()
                dismiss()
            } catch {
                errorMessage = UserFacingError.message(for: error)
            }
            isSaving = false
        }
    }
}
