//
//  CSVImporter.swift
//  AppStoreCodes
//
//  Created by Matteo Comisso on 08/12/2025.
//

import Foundation
import SwiftData

nonisolated struct ParsedCode: Sendable {
    let code: String
    let redemptionURL: String
    let appStoreId: String
}

private nonisolated enum CSVRowParser {
    static func parse(_ row: String) -> [String]? {
        var fields: [String] = []
        var field = ""
        var isInsideQuotes = false
        var index = row.startIndex

        while index < row.endIndex {
            let character = row[index]

            if character == "\"" {
                let nextIndex = row.index(after: index)
                if isInsideQuotes,
                   nextIndex < row.endIndex,
                   row[nextIndex] == "\"" {
                    field.append("\"")
                    index = row.index(after: nextIndex)
                    continue
                }
                isInsideQuotes.toggle()
            } else if character == "," && !isInsideQuotes {
                fields.append(field)
                field = ""
            } else {
                field.append(character)
            }

            index = row.index(after: index)
        }

        guard !isInsideQuotes else { return nil }
        fields.append(field)
        return fields
    }
}

nonisolated enum CSVCodeKind: Hashable, Sendable {
    case promo
    case offer
}

/// Dates inferred from the imported document for the confirmation UI. The
/// expiration date is a suggestion until the user confirms or edits it.
nonisolated struct CSVImportDates {
    let issueDate: Date
    let expirationDate: Date
    let codeKind: CSVCodeKind

    init(
        url: URL,
        csvContent: String? = nil,
        calendar: Calendar = .current,
        fallbackDate: Date = Date()
    ) {
        let accessedSecurityScopedResource = url.startAccessingSecurityScopedResource()
        defer {
            if accessedSecurityScopedResource {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let resourceValues = try? url.resourceValues(forKeys: [
            .contentModificationDateKey,
            .creationDateKey
        ])
        let documentDate = resourceValues?.contentModificationDate
            ?? resourceValues?.creationDate
            ?? fallbackDate
        let issueDate = calendar.startOfDay(for: documentDate)
        let content = csvContent ?? (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let codeKind = Self.inferCodeKind(from: content)

        self.issueDate = issueDate
        self.codeKind = codeKind
        self.expirationDate = Self.defaultExpirationDate(
            for: issueDate,
            codeKind: codeKind,
            calendar: calendar
        )
    }

    static func defaultExpirationDate(
        for issueDate: Date,
        codeKind: CSVCodeKind = .offer,
        calendar: Calendar = .current
    ) -> Date {
        let issueDay = calendar.startOfDay(for: issueDate)
        switch codeKind {
        case .promo:
            return calendar.date(byAdding: .day, value: 28, to: issueDay) ?? issueDay
        case .offer:
            return calendar.date(byAdding: .month, value: 6, to: issueDay) ?? issueDay
        }
    }

    static func inferCodeKind(from content: String) -> CSVCodeKind {
        let rows = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .compactMap(CSVRowParser.parse)

        if let firstField = rows.first?.first {
            let normalizedHeader = firstField
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"\u{FEFF}"))
                .lowercased()
                .filter { $0.isLetter || $0.isNumber }

            if normalizedHeader == "promocode" {
                return .promo
            }
            if normalizedHeader == "offercode" {
                return .offer
            }
        }

        let hasOfferRedemptionURL = rows.contains { fields in
            guard fields.count > 1,
                  let components = URLComponents(
                    string: fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
                  ) else { return false }

            return components.queryItems?.contains {
                $0.name.caseInsensitiveCompare("ctx") == .orderedSame &&
                    $0.value?.caseInsensitiveCompare("offercodes") == .orderedSame
            } == true
        }

        return hasOfferRedemptionURL ? .offer : .promo
    }
}

nonisolated struct CSVImportInspection: Sendable {
    let issueDate: Date
    let expirationDate: Date
    let codeKind: CSVCodeKind
}

nonisolated enum CSVImportError: LocalizedError, Sendable {
    case fileReadError
    case invalidFormat
    case noValidCodes
    case duplicateCodesFound(count: Int)
    case targetAppRequired
    case appStoreIdMismatch

    var errorDescription: String? {
        switch self {
        case .fileReadError:
            return "Could not read the CSV file."
        case .invalidFormat:
            return "The file format is invalid. Expected: CODE,REDEMPTION_URL"
        case .noValidCodes:
            return "No valid codes found in the file."
        case .duplicateCodesFound(let count):
            return "Found \(count) duplicate codes that were skipped."
        case .targetAppRequired:
            return "Choose an app before importing a file that contains codes without redemption URLs."
        case .appStoreIdMismatch:
            return "The file contains codes for more than one app, or does not match the selected app."
        }
    }
}

nonisolated struct CSVImportResult: Sendable {
    let importedCount: Int
    let skippedDuplicates: Int
    let appStoreId: String
    let batchId: UUID?
    let requiresMetadataRefresh: Bool
}

actor CSVImporter {
    nonisolated let modelContainer: ModelContainer
    private var storedModelContext: ModelContext?
    #if DEBUG
    private var shouldFailBeforeNextSave = false
    #endif

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    private var modelContext: ModelContext {
        if let storedModelContext {
            return storedModelContext
        }

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
        let content = try readCSV(from: url)
        let dates = CSVImportDates(url: url, csvContent: content)
        return CSVImportInspection(
            issueDate: dates.issueDate,
            expirationDate: dates.expirationDate,
            codeKind: dates.codeKind
        )
    }

    /// Imports codes from a CSV file URL
    /// - Parameters:
    ///   - url: The URL of the CSV file
    ///   - batchName: Optional name for the batch (defaults to filename)
    ///   - expirationDate: Optional expiration date for all codes in this batch
    /// - Returns: Import result with statistics
    func importCodes(
        from url: URL,
        batchName: String? = nil,
        expirationDate: Date? = nil,
        targetAppStoreId: String? = nil
    ) throws -> CSVImportResult {
        do {
            let content = try readCSV(from: url)
            try Task.checkCancellation()
            let importDates = CSVImportDates(url: url, csvContent: content)
            let effectiveExpirationDate = expirationDate ?? importDates.expirationDate
            let effectiveTargetAppStoreId = containsEmbeddedAppStoreID(in: content)
                ? nil
                : targetAppStoreId

            return try persistCodes(
                fromCSVString: content,
                batchName: batchName ?? url.deletingPathExtension().lastPathComponent,
                source: .csv,
                expirationDate: effectiveExpirationDate,
                targetAppStoreId: effectiveTargetAppStoreId,
                targetAppName: nil
            )
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// Imports codes from a CSV string (used by API imports)
    /// - Parameters:
    ///   - csvString: The CSV content as a string
    ///   - batchName: Name for the batch
    ///   - source: The import source (.csv or .api)
    ///   - expirationDate: Optional expiration date for all codes in this batch
    /// - Returns: Import result with statistics
    func importCodes(
        fromCSVString csvString: String,
        batchName: String,
        source: ImportSource = .csv,
        expirationDate: Date? = nil,
        targetAppStoreId: String? = nil,
        targetAppName: String? = nil
    ) throws -> CSVImportResult {
        do {
            return try persistCodes(
                fromCSVString: csvString,
                batchName: batchName,
                source: source,
                expirationDate: expirationDate,
                targetAppStoreId: targetAppStoreId,
                targetAppName: targetAppName
            )
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func persistCodes(
        fromCSVString csvString: String,
        batchName: String,
        source: ImportSource,
        expirationDate: Date?,
        targetAppStoreId: String?,
        targetAppName: String?
    ) throws -> CSVImportResult {
        try Task.checkCancellation()
        let effectiveCodeKind = CSVImportDates.inferCodeKind(from: csvString)
        let effectiveExpirationDate = expirationDate ?? (source == .csv
            ? CSVImportDates.defaultExpirationDate(for: Date(), codeKind: effectiveCodeKind)
            : nil)

        // Parse CSV content
        let parsedCodes = try parseCSV(
            csvString,
            targetAppStoreId: targetAppStoreId
        )

        guard !parsedCodes.isEmpty else {
            throw CSVImportError.noValidCodes
        }

        // Parsing guarantees that every row belongs to the same app.
        guard let appStoreId = parsedCodes.first?.appStoreId else {
            throw CSVImportError.noValidCodes
        }

        // Find or create the App
        let (app, isNewApp) = try findOrCreateApp(
            appStoreId: appStoreId,
            preferredName: targetAppName
        )
        let didUpdateAppName = targetAppName.map { app.name != $0 } ?? false
        if let targetAppName, didUpdateAppName {
            app.name = targetAppName
        }
        let requiresMetadataRefresh = isNewApp || !app.hasMetadata

        // Get existing codes for this app to detect duplicates
        var seenCodes = Set((app.codes ?? []).map { $0.code })

        // Filter duplicates before inserting a batch so an all-duplicate import
        // does not leave an empty batch behind.
        var codesToImport: [ParsedCode] = []
        var skippedDuplicates = 0

        for parsed in parsedCodes {
            try Task.checkCancellation()
            if seenCodes.contains(parsed.code) {
                skippedDuplicates += 1
                continue
            }

            seenCodes.insert(parsed.code)
            codesToImport.append(parsed)
        }

        guard !codesToImport.isEmpty else {
            if didUpdateAppName {
                try modelContext.save()
            }
            return CSVImportResult(
                importedCount: 0,
                skippedDuplicates: skippedDuplicates,
                appStoreId: appStoreId,
                batchId: nil,
                requiresMetadataRefresh: requiresMetadataRefresh
            )
        }

        let batch = CodeBatch(
            name: batchName,
            source: source,
            expirationDate: effectiveExpirationDate
        )
        batch.app = app
        modelContext.insert(batch)

        for parsed in codesToImport {
            try Task.checkCancellation()
            let offerCode = OfferCode(
                code: parsed.code,
                redemptionURL: parsed.redemptionURL,
                expirationDate: effectiveExpirationDate
            )
            offerCode.app = app
            offerCode.batch = batch
            modelContext.insert(offerCode)
        }

        #if DEBUG
        if shouldFailBeforeNextSave {
            shouldFailBeforeNextSave = false
            throw CSVImporterTestError.forcedFailure
        }
        #endif

        // Save changes
        try modelContext.save()

        return CSVImportResult(
            importedCount: codesToImport.count,
            skippedDuplicates: skippedDuplicates,
            appStoreId: appStoreId,
            batchId: batch.id,
            requiresMetadataRefresh: requiresMetadataRefresh
        )
    }

    /// Fills expiration dates for CSV batches imported before document-based
    /// expiration defaults were introduced. The original document date was not
    /// persisted, so the retained batch import date is the best available proxy.
    @discardableResult
    func backfillMissingCSVExpirationDates(calendar: Calendar = .current) throws -> Int {
        do {
            let batches = try modelContext.fetch(FetchDescriptor<CodeBatch>())
            var updatedCodeCount = 0
            var hasChanges = false

            for batch in batches where batch.source == .csv {
                try Task.checkCancellation()
                let expirationDate = batch.expirationDate
                    ?? CSVImportDates.defaultExpirationDate(
                        for: batch.importDate,
                        calendar: calendar
                    )

                if batch.expirationDate == nil {
                    batch.expirationDate = expirationDate
                    hasChanges = true
                }

                for code in batch.codes ?? [] where code.expirationDate == nil {
                    code.expirationDate = expirationDate
                    updatedCodeCount += 1
                    hasChanges = true
                }
            }

            if hasChanges {
                try modelContext.save()
            }

            return updatedCodeCount
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// Parses CSV content into ParsedCode array
    private func parseCSV(
        _ content: String,
        targetAppStoreId: String?
    ) throws -> [ParsedCode] {
        var results: [ParsedCode] = []
        var discoveredAppStoreId = targetAppStoreId

        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for line in lines {
            try Task.checkCancellation()
            guard let components = CSVRowParser.parse(line), !components.isEmpty else {
                continue
            }

            let code = normalizedField(components[0])

            if isHeader(code) {
                continue
            }

            guard isValidCode(code) else { continue }

            let suppliedURL = components.count > 1
                ? normalizedField(components[1])
                : ""
            let urlAppStoreId = suppliedURL.isEmpty
                ? nil
                : extractAppStoreId(from: suppliedURL)

            if let targetAppStoreId,
               let urlAppStoreId,
               targetAppStoreId != urlAppStoreId {
                throw CSVImportError.appStoreIdMismatch
            }

            if let urlAppStoreId {
                if let discoveredAppStoreId,
                   discoveredAppStoreId != urlAppStoreId {
                    throw CSVImportError.appStoreIdMismatch
                }
                discoveredAppStoreId = urlAppStoreId
            }

            guard let appStoreId = urlAppStoreId ?? targetAppStoreId else {
                if suppliedURL.isEmpty {
                    throw CSVImportError.targetAppRequired
                }
                continue
            }

            let redemptionURL = suppliedURL.isEmpty
                ? makeRedemptionURL(code: code, appStoreId: appStoreId)
                : suppliedURL

            results.append(ParsedCode(
                code: code,
                redemptionURL: redemptionURL,
                appStoreId: appStoreId
            ))
        }

        return results
    }

    /// Apple-generated and custom offer codes vary in length. Apple limits
    /// custom codes to 64 ASCII alphanumeric characters.
    private func isValidCode(_ code: String) -> Bool {
        guard (1...64).contains(code.utf8.count) else { return false }
        return code.utf8.allSatisfy { byte in
            (48...57).contains(byte) ||
                (65...90).contains(byte) ||
                (97...122).contains(byte)
        }
    }

    private func normalizedField(_ field: String) -> String {
        field.trimmingCharacters(
            in: .whitespacesAndNewlines.union(
                CharacterSet(charactersIn: "\u{FEFF}")
            )
        )
    }

    private func isHeader(_ field: String) -> Bool {
        let normalized = field
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        return normalized == "code" ||
            normalized == "offercode" ||
            normalized == "promocode"
    }

    private func containsEmbeddedAppStoreID(in content: String) -> Bool {
        content.components(separatedBy: .newlines).contains { line in
            guard let fields = CSVRowParser.parse(line), fields.count > 1 else {
                return false
            }
            return extractAppStoreId(from: normalizedField(fields[1])) != nil
        }
    }

    private func makeRedemptionURL(code: String, appStoreId: String) -> String {
        var components = URLComponents(string: "https://apps.apple.com/redeem")!
        components.queryItems = [
            URLQueryItem(name: "ctx", value: "offercodes"),
            URLQueryItem(name: "id", value: appStoreId),
            URLQueryItem(name: "code", value: code),
        ]
        return components.url!.absoluteString
    }

    /// Extracts the App Store ID from the redemption URL
    /// URL format: https://apps.apple.com/redeem?ctx=offercodes&id=1547173908&code=...
    private func extractAppStoreId(from urlString: String) -> String? {
        guard let url = URL(string: urlString),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return nil
        }

        return queryItems.first { $0.name == "id" }?.value
    }

    /// Finds an existing AppRecord by App Store ID or creates a new one
    private func findOrCreateApp(
        appStoreId: String,
        preferredName: String?
    ) throws -> (app: AppRecord, isNew: Bool) {
        let descriptor = FetchDescriptor<AppRecord>(
            predicate: #Predicate { $0.appStoreId == appStoreId }
        )

        if let existingApp = try modelContext.fetch(descriptor).first {
            return (existingApp, false)
        }

        // Create new app with placeholder name
        let newApp = AppRecord(
            name: preferredName ?? "App \(appStoreId)",
            appStoreId: appStoreId
        )
        modelContext.insert(newApp)
        return (newApp, true)
    }

    private func readCSV(from url: URL) throws -> String {
        // Security-scoped URLs need balanced access. Regular local URLs can
        // legitimately return false and should still be read normally.
        let accessedSecurityScopedResource = url.startAccessingSecurityScopedResource()
        defer {
            if accessedSecurityScopedResource {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw CSVImportError.fileReadError
        }
    }
}

#if DEBUG
nonisolated enum CSVImporterTestError: Error {
    case forcedFailure
}
#endif
