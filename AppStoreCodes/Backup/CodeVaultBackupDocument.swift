import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let codeVaultBackup = UTType(exportedAs: "app.pythonide.codevault.backup")
}

struct CodeVaultBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.codeVaultBackup, .json] }

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
