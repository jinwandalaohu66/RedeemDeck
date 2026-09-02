import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let redeemDeckBackup = UTType(
        exportedAs: "app.pythonide.redeemdeck.backup",
        conformingTo: .json
    )

    // Import-only compatibility for backups exported before the product rename.
    static let codeVaultBackupImportType = UTType(
        importedAs: "app.pythonide.codevault.backup",
        conformingTo: .json
    )
}

struct RedeemDeckBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.redeemDeckBackup, .codeVaultBackupImportType, .json]
    }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw BackupCodecError.invalidArchive
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
