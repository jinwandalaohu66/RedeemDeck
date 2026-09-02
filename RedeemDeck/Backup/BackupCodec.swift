import Foundation

nonisolated enum BackupCodecError: LocalizedError, Sendable {
    case fileTooLarge
    case unsupportedVersion
    case invalidArchive

    var errorDescription: String? {
        switch self {
        case .fileTooLarge: String(localized: "The backup file is too large.")
        case .unsupportedVersion: String(localized: "This backup was created by an unsupported version of RedeemDeck.")
        case .invalidArchive: String(localized: "The selected file is not a valid RedeemDeck backup.")
        }
    }
}

actor BackupCodec {
    static let shared = BackupCodec()

    private let maximumFileSize = 100 * 1_024 * 1_024
    private let maximumRecordCount = 1_000_000

    func encode(_ archive: RedeemDeckBackupArchive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(archive)
    }

    func decode(_ data: Data) throws -> RedeemDeckBackupArchive {
        guard data.count <= maximumFileSize else {
            throw BackupCodecError.fileTooLarge
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let archive = try? decoder.decode(RedeemDeckBackupArchive.self, from: data) else {
            throw BackupCodecError.invalidArchive
        }
        guard (1...RedeemDeckBackupArchive.currentVersion).contains(archive.schemaVersion) else {
            throw BackupCodecError.unsupportedVersion
        }
        let recordCount = archive.apps.count
            + (archive.categories?.count ?? 0)
            + archive.batches.count
            + archive.codes.count
            + archive.campaigns.count
            + archive.recipients.count
            + archive.distributions.count
            + archive.activities.count
            + archive.templates.count
        guard recordCount <= maximumRecordCount else {
            throw BackupCodecError.fileTooLarge
        }
        return archive
    }
}
