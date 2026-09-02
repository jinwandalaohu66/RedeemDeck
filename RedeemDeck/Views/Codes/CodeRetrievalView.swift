import SwiftUI

struct CodeRetrievalView: View {
    let request: CodeRetrievalRequest
    let repository: RedeemDeckRepository

    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    @Environment(AppFeedbackCenter.self) private var feedback
    @State private var selection: PreparedCodeSelection?
    @State private var isLoading = true
    @State private var isWorking = false
    @State private var isConfirmingRelease = false
    @State private var errorMessage: String?

    var body: some View {
        content
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { releaseToolbar }
            .disabled(isWorking)
            .overlay { if isWorking { ProgressView("Working") } }
            .task(id: request.id) { await loadSelection() }
            .alert(
                "Return pending codes to inventory?",
                isPresented: $isConfirmingRelease
            ) {
                Button("Return to Inventory", role: .destructive, action: releasePendingCodes)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Only codes that have not been sent will become available again.")
            }
            .alert(
                "Unable to Complete Action",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? String(localized: "The operation could not be completed. Please try again."))
            }
    }

    @ViewBuilder
    private var content: some View {
        if let selection {
            CodeRetrievalResultView(
                selection: Binding(
                    get: { self.selection ?? selection },
                    set: { self.selection = $0 }
                ),
                repository: repository
            )
        } else if isLoading {
            ProgressView("Getting Codes")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView {
                Label("Unable to Get Codes", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage ?? String(localized: "The operation could not be completed. Please try again."))
            } actions: {
                Button("Try Again") { Task { await loadSelection() } }
            }
        }
    }

    private var title: String {
        guard let selection else { return String(localized: "Get Codes") }
        return selection.codes.count == 1
            ? String(localized: "Retrieved 1 Code")
            : String(localized: "Retrieved \(selection.codes.count) Codes")
    }

    @ToolbarContentBuilder
    private var releaseToolbar: some ToolbarContent {
        if selection?.isPending == true {
            ToolbarItem(placement: .primaryAction) {
                Button("Return to Inventory", systemImage: "arrow.uturn.backward") {
                    isConfirmingRelease = true
                }
            }
        }
    }

    private func loadSelection() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded: PreparedCodeSelection
            if let selectionID = request.selectionID {
                guard let value = try await repository.loadSelection(id: selectionID) else {
                    throw RedeemDeckRepositoryError.selectionNotFound
                }
                loaded = value
            } else {
                guard let categoryID = request.categoryID, let quantity = request.quantity else {
                    throw RedeemDeckRepositoryError.invalidQuantity
                }
                loaded = try await repository.reserveCodes(
                    categoryID: categoryID,
                    quantity: quantity
                )
                session.dataDidChange()
            }
            guard !Task.isCancelled else { return }
            selection = loaded
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = UserFacingError.message(for: error)
        }
    }

    private func releasePendingCodes() {
        guard let selection else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let count = try await repository.releaseSelection(id: selection.id)
                session.dataDidChange()
                feedback.show(String(localized: "Returned \(count) Codes to Inventory"))
                dismiss()
            } catch {
                errorMessage = UserFacingError.message(for: error)
            }
        }
    }
}
