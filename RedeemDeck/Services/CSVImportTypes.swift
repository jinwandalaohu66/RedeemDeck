import Foundation

nonisolated struct ParsedCode: Sendable {
    let code: String
    let redemptionURL: String
    let appStoreId: String
}

nonisolated enum CSVCodeKind: Hashable, Sendable {
    case promo
    case offer
}

nonisolated struct CSVImportInspection: Sendable {
    let issueDate: Date
    let expirationDate: Date
    let codeKind: CSVCodeKind
    let detectedAppStoreID: String?
}

nonisolated enum CSVImportError: LocalizedError, Sendable {
    case fileReadError
    case invalidFormat
    case noValidCodes
    case duplicateCodesFound(count: Int)
    case targetAppRequired
    case appStoreIdMismatch
    case categoryNotFound
    case categoryAppMismatch

    var errorDescription: String? {
        switch self {
        case .fileReadError:
            String(localized: "Could not read the CSV file.")
        case .invalidFormat:
            String(localized: "The file format is invalid. Expected: CODE,REDEMPTION_URL")
        case .noValidCodes:
            String(localized: "No valid codes found in the file.")
        case .duplicateCodesFound(let count):
            String(localized: "Found \(count) duplicate codes that were skipped.")
        case .targetAppRequired:
            String(localized: "Choose an app before importing a file that contains codes without redemption URLs.")
        case .appStoreIdMismatch:
            String(localized: "The file contains codes for more than one app, or does not match the selected app.")
        case .categoryNotFound:
            String(localized: "The selected code category no longer exists.")
        case .categoryAppMismatch:
            String(localized: "The selected code category belongs to a different app.")
        }
    }
}

nonisolated struct CSVImportResult: Sendable {
    let importedCount: Int
    let skippedDuplicates: Int
    let appStoreId: String
    let batchId: UUID?
    let categoryID: UUID?
    let requiresMetadataRefresh: Bool
}

#if DEBUG
nonisolated enum CSVImporterTestError: Error {
    case forcedFailure
}
#endif
