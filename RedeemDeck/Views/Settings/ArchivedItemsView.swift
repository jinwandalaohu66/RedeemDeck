import SwiftData
import SwiftUI

struct ArchivedItemsView: View {
    let repository: RedeemDeckRepository

    @Environment(AppSession.self) private var session
    @Query(
        filter: #Predicate<AppRecord> { $0.archivedAt != nil },
        sort: \AppRecord.name
    ) private var archivedApps: [AppRecord]
    @Query(
        filter: #Predicate<CodeCategory> { $0.archivedAt != nil },
        sort: \CodeCategory.name
    ) private var archivedCategories: [CodeCategory]
    @Query(
        filter: #Predicate<CodeBatch> { $0.archivedAt != nil },
        sort: \CodeBatch.importDate,
        order: .reverse
    ) private var archivedBatches: [CodeBatch]
    @Environment(AppFeedbackCenter.self) private var feedback
    @State private var workingIDs: Set<UUID> = []
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section("Apps") {
                ForEach(archivedApps) { app in
                    restoreRow(title: app.name, target: .app(app.id))
                }
            }
            Section("Code Categories") {
                ForEach(archivedCategories) { category in
                    restoreRow(title: category.name, target: .category(category.id))
                }
            }
            Section("Import Batches") {
                ForEach(archivedBatches) { batch in
                    restoreRow(title: batch.name, target: .batch(batch.id))
                }
            }
        }
        .navigationTitle("Archived Items")
        .overlay {
            if archivedApps.isEmpty && archivedCategories.isEmpty && archivedBatches.isEmpty {
                ContentUnavailableView("No Archived Items", systemImage: "archivebox")
            }
        }
        .alert(
            "Unable to Restore",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? String(localized: "The item could not be restored."))
        }
    }

    private func restoreRow(title: String, target: ArchiveTarget) -> some View {
        LabeledContent(title) {
            Button("Restore") { restore(target) }
                .disabled(workingIDs.contains(target.id))
        }
    }

    private func restore(_ target: ArchiveTarget) {
        workingIDs.insert(target.id)
        Task {
            do {
                try await repository.setArchived(target, archived: false)
                session.dataDidChange()
                feedback.show(String(localized: "Item restored."))
            } catch {
                errorMessage = UserFacingError.message(for: error)
            }
            workingIDs.remove(target.id)
        }
    }
}
