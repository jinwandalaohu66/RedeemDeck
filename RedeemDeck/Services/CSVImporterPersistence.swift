import Foundation
import SwiftData

extension CSVImporter {
    func persistCodes(
        fromCSVString csvString: String,
        batchName: String,
        source: ImportSource,
        expirationDate: Date?,
        targetAppStoreId: String?,
        targetAppName: String?,
        codeKind: CodeKind?,
        environment: CodeEnvironment,
        platform: AppPlatform,
        appVersion: String?,
        category input: CodeCategoryInput?
    ) throws -> CSVImportResult {
        try Task.checkCancellation()
        let inferredKind = CSVImportDates.inferCodeKind(from: csvString)
        let effectiveExpiration = expirationDate ?? (source == .csv
            ? CSVImportDates.defaultExpirationDate(for: Date(), codeKind: inferredKind)
            : nil)
        let parsedCodes = try CSVDocumentParser.parse(
            csvString,
            targetAppStoreId: targetAppStoreId
        )
        guard let appStoreId = parsedCodes.first?.appStoreId else {
            throw CSVImportError.noValidCodes
        }

        let (app, isNewApp) = try findOrCreateApp(
            appStoreId: appStoreId,
            preferredName: targetAppName
        )
        let didUpdateName = targetAppName.map { app.name != $0 } ?? false
        if let targetAppName, didUpdateName { app.name = targetAppName }

        let appID = app.id
        let existingCodes = try modelContext.fetch(FetchDescriptor<OfferCode>(
            predicate: #Predicate { $0.app?.id == appID }
        ))
        var seenCodes = Set(existingCodes.map(\.code))
        var codesToImport: [ParsedCode] = []
        var skippedDuplicates = 0

        for parsed in parsedCodes {
            try Task.checkCancellation()
            guard seenCodes.insert(parsed.code).inserted else {
                skippedDuplicates += 1
                continue
            }
            codesToImport.append(parsed)
        }

        let requiresMetadataRefresh = isNewApp || !app.hasMetadata
        guard !codesToImport.isEmpty else {
            if didUpdateName { try modelContext.save() }
            return CSVImportResult(
                importedCount: 0,
                skippedDuplicates: skippedDuplicates,
                appStoreId: appStoreId,
                batchId: nil,
                categoryID: input?.existingID,
                requiresMetadataRefresh: requiresMetadataRefresh
            )
        }

        let category = try resolveCategory(input, for: app, fallbackName: batchName)

        let batch = CodeBatch(
            name: batchName,
            source: source,
            expirationDate: effectiveExpiration
        )
        batch.app = app
        batch.codeKind = codeKind ?? domainCodeKind(from: inferredKind)
        batch.environment = environment
        batch.platform = platform
        batch.appVersion = appVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
        batch.category = category
        // Keep the former batch metadata populated for old backups and stores.
        batch.productID = category.productID
        batch.offerReferenceName = category.offerReferenceName
        modelContext.insert(batch)

        for parsed in codesToImport {
            try Task.checkCancellation()
            let code = OfferCode(
                code: parsed.code,
                redemptionURL: parsed.redemptionURL,
                expirationDate: effectiveExpiration
            )
            code.app = app
            code.batch = batch
            modelContext.insert(code)
        }

        #if DEBUG
        if shouldFailBeforeNextSave {
            shouldFailBeforeNextSave = false
            throw CSVImporterTestError.forcedFailure
        }
        #endif

        try modelContext.save()
        return CSVImportResult(
            importedCount: codesToImport.count,
            skippedDuplicates: skippedDuplicates,
            appStoreId: appStoreId,
            batchId: batch.id,
            categoryID: category.id,
            requiresMetadataRefresh: requiresMetadataRefresh
        )
    }

    @discardableResult
    func backfillMissingCSVExpirationDates(calendar: Calendar = .current) throws -> Int {
        do {
            let batches = try modelContext.fetch(FetchDescriptor<CodeBatch>())
            var updatedCount = 0
            var hasChanges = false

            for batch in batches where batch.source == .csv {
                try Task.checkCancellation()
                let expiration = batch.expirationDate
                    ?? CSVImportDates.defaultExpirationDate(
                        for: batch.importDate,
                        calendar: calendar
                    )
                if batch.expirationDate == nil {
                    batch.expirationDate = expiration
                    hasChanges = true
                }
                for code in batch.codes ?? [] where code.expirationDate == nil {
                    code.expirationDate = expiration
                    updatedCount += 1
                    hasChanges = true
                }
            }
            if hasChanges { try modelContext.save() }
            return updatedCount
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func findOrCreateApp(
        appStoreId: String,
        preferredName: String?
    ) throws -> (app: AppRecord, isNew: Bool) {
        let descriptor = FetchDescriptor<AppRecord>(
            predicate: #Predicate { $0.appStoreId == appStoreId }
        )
        if let app = try modelContext.fetch(descriptor).first { return (app, false) }
        let app = AppRecord(
            name: preferredName ?? "App \(appStoreId)",
            appStoreId: appStoreId
        )
        modelContext.insert(app)
        return (app, true)
    }

    private func resolveCategory(
        _ input: CodeCategoryInput?,
        for app: AppRecord,
        fallbackName: String
    ) throws -> CodeCategory {
        if let id = input?.existingID {
            guard let category = try modelContext.fetch(FetchDescriptor<CodeCategory>(
                predicate: #Predicate { $0.id == id }
            )).first else {
                throw CSVImportError.categoryNotFound
            }
            guard category.app?.id == app.id else {
                throw CSVImportError.categoryAppMismatch
            }
            return category
        }

        let category = CodeCategory(
            name: input?.name.nilIfBlank ?? fallbackName,
            productName: input?.productName.nilIfBlank ?? String(localized: "General"),
            productID: input?.productID?.nilIfBlank,
            offerReferenceName: input?.offerReferenceName?.nilIfBlank,
            app: app
        )
        modelContext.insert(category)
        return category
    }

    private func domainCodeKind(from kind: CSVCodeKind) -> CodeKind {
        switch kind {
        case .promo: .appPromo
        case .offer: .oneTimeOffer
        }
    }
}
