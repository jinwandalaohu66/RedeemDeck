import SwiftUI

struct RestorePreviewSheet: View {
    let preview: RestorePreview
    let repository: BackupRepository
    let onComplete: (BackupRestoreSummary) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isRestoring = false
    @State private var errorMessage: String?

    private var archive: RedeemDeckBackupArchive {
        preview.archive
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Backup") {
                    LabeledContent("Created") {
                        Text(archive.createdAt, format: .dateTime.year().month().day().hour().minute())
                    }
                    LabeledContent("Apps", value: "\(archive.apps.count)")
                    LabeledContent("Code Categories", value: "\(archive.categories?.count ?? 0)")
                    LabeledContent("Batches", value: "\(archive.batches.count)")
                    LabeledContent("Codes", value: "\(archive.codes.count)")
                }
                Section {
                    Text("Matching records will be updated and missing records will be added. Current records that are not in this backup will remain unchanged.")
                }
            }
            .navigationTitle("Review Restore")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Restore", action: restore)
                        .disabled(isRestoring)
                }
            }
            .disabled(isRestoring)
            .overlay {
                if isRestoring {
                    ProgressView("Restoring")
                }
            }
            .alert(
                "Restore Failed",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? String(localized: "The backup could not be restored."))
            }
        }
    }

    private func restore() {
        isRestoring = true
        Task {
            do {
                let summary = try await repository.restore(archive)
                isRestoring = false
                dismiss()
                onComplete(summary)
            } catch {
                isRestoring = false
                errorMessage = UserFacingError.message(for: error)
            }
        }
    }
}
