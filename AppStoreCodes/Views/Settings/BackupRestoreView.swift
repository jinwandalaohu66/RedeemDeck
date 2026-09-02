import SwiftUI
import UniformTypeIdentifiers

struct BackupRestoreView: View {
    let repository: BackupRepository

    @Environment(AppSession.self) private var session
    @Environment(AppFeedbackCenter.self) private var feedback
    @State private var exportDocument = CodeVaultBackupDocument()
    @State private var exportFilename = "CodeVault Backup"
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var isWorking = false
    @State private var restorePreview: RestorePreview?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section("Backup") {
                Button("Export Complete Backup", action: prepareExport)
                Text("The backup includes apps, code categories, import batches, codes, and delivery state.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Backup files contain complete, unmasked codes. Store and share them securely.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Restore") {
                Button("Choose Backup File", action: chooseBackup)
                Text("Restore merges matching records by their stable identifiers. Existing data is not deleted.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Backup and Restore")
        .disabled(isWorking)
        .overlay {
            if isWorking {
                ProgressView("Preparing Data")
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .codeVaultBackup,
            defaultFilename: exportFilename,
            onCompletion: handleExport
        )
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.codeVaultBackup, .json],
            allowsMultipleSelection: false,
            onCompletion: handleImport
        )
        .sheet(item: $restorePreview) { preview in
            RestorePreviewSheet(
                preview: preview,
                repository: repository,
                onComplete: finishRestore
            )
            .codeVaultFormPresentation()
        }
        .alert(
            "Backup Operation Failed",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? String(localized: "The backup operation could not be completed."))
        }
    }

    private func prepareExport() {
        isWorking = true
        Task {
            do {
                let archive = try await repository.makeArchive()
                let data = try await BackupCodec.shared.encode(archive)
                exportDocument = CodeVaultBackupDocument(data: data)
                exportFilename = "CodeVault \(Date().formatted(.iso8601.year().month().day()))"
                isExporting = true
            } catch {
                errorMessage = UserFacingError.message(for: error)
            }
            isWorking = false
        }
    }

    private func chooseBackup() {
        isImporting = true
    }

    private func handleExport(_ result: Result<URL, Error>) {
        if case .success = result {
            feedback.show(String(localized: "Backup exported."))
        } else if case .failure(let error) = result {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            inspectBackup(at: url)
        case .failure(let error):
            errorMessage = UserFacingError.message(for: error)
        }
    }

    private func inspectBackup(at url: URL) {
        isWorking = true
        Task {
            do {
                let data = try await BackupFileReader.shared.read(from: url)
                let archive = try await BackupCodec.shared.decode(data)
                restorePreview = RestorePreview(archive: archive)
            } catch {
                errorMessage = UserFacingError.message(for: error)
            }
            isWorking = false
        }
    }

    private func finishRestore(_ summary: BackupRestoreSummary) {
        restorePreview = nil
        session.dataDidChange()
        feedback.show(String(
            localized: "Restored \(summary.apps) apps, \(summary.categories) code categories, and \(summary.codes) codes."
        ))
    }
}

struct RestorePreview: Identifiable {
    let id = UUID()
    let archive: CodeVaultBackupArchive
}
