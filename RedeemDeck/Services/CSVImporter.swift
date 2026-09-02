import Foundation
import SwiftData

actor CSVImporter {
    nonisolated let modelContainer: ModelContainer
    var storedModelContext: ModelContext?
    #if DEBUG
    var shouldFailBeforeNextSave = false
    #endif

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    var modelContext: ModelContext {
        if let storedModelContext { return storedModelContext }
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        storedModelContext = context
        return context
    }

    #if DEBUG
    func failBeforeNextSaveForTesting() {
        shouldFailBeforeNextSave = true
    }
    #endif

    func inspect(_ url: URL) throws -> CSVImportInspection {
        let content = try CSVFileReader.read(url)
        let dates = CSVImportDates(url: url, csvContent: content)
        return CSVImportInspection(
            issueDate: dates.issueDate,
            expirationDate: dates.expirationDate,
            codeKind: dates.codeKind,
            detectedAppStoreID: CSVDocumentParser.detectedAppStoreID(in: content)
        )
    }

    func importCodes(
        from url: URL,
        batchName: String? = nil,
        expirationDate: Date? = nil,
        targetAppStoreId: String? = nil,
        codeKind: CodeKind? = nil,
        environment: CodeEnvironment = .production,
        platform: AppPlatform = .iOS,
        appVersion: String? = nil,
        category: CodeCategoryInput? = nil
    ) throws -> CSVImportResult {
        do {
            let content = try CSVFileReader.read(url)
            try Task.checkCancellation()
            let dates = CSVImportDates(url: url, csvContent: content)
            let targetID = CSVDocumentParser.containsEmbeddedAppStoreID(in: content)
                ? nil
                : targetAppStoreId
            return try persistCodes(
                fromCSVString: content,
                batchName: batchName ?? url.deletingPathExtension().lastPathComponent,
                source: .csv,
                expirationDate: expirationDate ?? dates.expirationDate,
                targetAppStoreId: targetID,
                targetAppName: nil,
                codeKind: codeKind,
                environment: environment,
                platform: platform,
                appVersion: appVersion,
                category: category
            )
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func importCodes(
        fromCSVString csvString: String,
        batchName: String,
        source: ImportSource = .csv,
        expirationDate: Date? = nil,
        targetAppStoreId: String? = nil,
        targetAppName: String? = nil,
        codeKind: CodeKind? = nil,
        environment: CodeEnvironment = .production,
        platform: AppPlatform = .iOS,
        appVersion: String? = nil,
        category: CodeCategoryInput? = nil
    ) throws -> CSVImportResult {
        do {
            return try persistCodes(
                fromCSVString: csvString,
                batchName: batchName,
                source: source,
                expirationDate: expirationDate,
                targetAppStoreId: targetAppStoreId,
                targetAppName: targetAppName,
                codeKind: codeKind,
                environment: environment,
                platform: platform,
                appVersion: appVersion,
                category: category
            )
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}
