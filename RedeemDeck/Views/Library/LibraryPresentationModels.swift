import Foundation

struct ImportDraft: Identifiable {
    let id = UUID()
    let url: URL
    let issueDate: Date
    let suggestedExpirationDate: Date
    let inferredKind: CodeKind
    let detectedAppStoreID: String?

    init(url: URL, inspection: CSVImportInspection) {
        self.url = url
        issueDate = inspection.issueDate
        suggestedExpirationDate = inspection.expirationDate
        inferredKind = inspection.codeKind == .promo ? .appPromo : .oneTimeOffer
        detectedAppStoreID = inspection.detectedAppStoreID
    }
}

struct ImportOutcome: Identifiable {
    let id = UUID()
    let message: String

    init(result: CSVImportResult) {
        if result.skippedDuplicates == 0 {
            message = String(localized: "Imported \(result.importedCount) codes.")
        } else {
            message = String(
                localized: "Imported \(result.importedCount) codes and skipped \(result.skippedDuplicates) duplicates."
            )
        }
    }
}

struct PendingRetrievalPresentation: Identifiable {
    let selection: PreparedCodeSelection
    let app: AppSummary

    var id: UUID { selection.id }
}
