//
//  CSVImporter.swift
//  AppStoreCodes
//
//  Created by Matteo Comisso on 08/12/2025.
//

import Foundation
import SwiftData

struct ParsedCode {
    let code: String
    let redemptionURL: String
    let appStoreId: String
}

struct CSVImportDates {
    let issueDate: Date
    let expirationDate: Date

    init(url: URL, calendar: Calendar = .current, fallbackDate: Date = Date()) {
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

        self.issueDate = issueDate
        self.expirationDate = Self.defaultExpirationDate(
            for: issueDate,
            calendar: calendar
        )
    }

    static func defaultExpirationDate(
        for issueDate: Date,
        calendar: Calendar = .current
    ) -> Date {
        let issueDay = calendar.startOfDay(for: issueDate)
        return calendar.date(byAdding: .month, value: 6, to: issueDay) ?? issueDay
    }
}

enum CSVImportError: LocalizedError {
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

struct CSVImportResult {
    let importedCount: Int
    let skippedDuplicates: Int
    let appStoreId: String
    let batchId: UUID?
}

final class CSVImporter {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
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
        targetApp: AppRecord? = nil
    ) throws -> CSVImportResult {
        // Security-scoped URLs need balanced access. Regular local URLs can
        // legitimately return false and should still be read normally.
        let accessedSecurityScopedResource = url.startAccessingSecurityScopedResource()
        defer {
            if accessedSecurityScopedResource {
                url.stopAccessingSecurityScopedResource()
            }
        }

        // Read file contents
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw CSVImportError.fileReadError
        }

        let effectiveExpirationDate = expirationDate ?? CSVImportDates(url: url).expirationDate

        return try importCodes(
            fromCSVString: content,
            batchName: batchName ?? url.deletingPathExtension().lastPathComponent,
            source: .csv,
            expirationDate: effectiveExpirationDate,
            targetApp: targetApp
        )
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
        targetApp: AppRecord? = nil
    ) throws -> CSVImportResult {
        // Parse CSV content
        let parsedCodes = try parseCSV(
            csvString,
            targetAppStoreId: targetApp?.appStoreId
        )

        guard !parsedCodes.isEmpty else {
            throw CSVImportError.noValidCodes
        }

        // Parsing guarantees that every row belongs to the same app.
        guard let appStoreId = parsedCodes.first?.appStoreId else {
            throw CSVImportError.noValidCodes
        }

        // Find or create the App
        let app = targetApp ?? findOrCreateApp(appStoreId: appStoreId)

        // Get existing codes for this app to detect duplicates
        var seenCodes = Set((app.codes ?? []).map { $0.code })

        // Filter duplicates before inserting a batch so an all-duplicate import
        // does not leave an empty batch behind.
        var codesToImport: [ParsedCode] = []
        var skippedDuplicates = 0

        for parsed in parsedCodes {
            if seenCodes.contains(parsed.code) {
                skippedDuplicates += 1
                continue
            }

            seenCodes.insert(parsed.code)
            codesToImport.append(parsed)
        }

        guard !codesToImport.isEmpty else {
            return CSVImportResult(
                importedCount: 0,
                skippedDuplicates: skippedDuplicates,
                appStoreId: appStoreId,
                batchId: nil
            )
        }

        let batch = CodeBatch(
            name: batchName,
            source: source,
            expirationDate: expirationDate
        )
        batch.app = app
        modelContext.insert(batch)

        for parsed in codesToImport {
            let offerCode = OfferCode(code: parsed.code, redemptionURL: parsed.redemptionURL, expirationDate: expirationDate)
            offerCode.app = app
            offerCode.batch = batch
            modelContext.insert(offerCode)
        }

        // Save changes
        try modelContext.save()

        return CSVImportResult(
            importedCount: codesToImport.count,
            skippedDuplicates: skippedDuplicates,
            appStoreId: appStoreId,
            batchId: batch.id
        )
    }

    /// Fills expiration dates for CSV batches imported before document-based
    /// expiration defaults were introduced. The original document date was not
    /// persisted, so the retained batch import date is the best available proxy.
    @discardableResult
    func backfillMissingCSVExpirationDates(calendar: Calendar = .current) throws -> Int {
        let batches = try modelContext.fetch(FetchDescriptor<CodeBatch>())
        var updatedCodeCount = 0
        var hasChanges = false

        for batch in batches where batch.source == .csv {
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
            guard let components = parseCSVRow(line), !components.isEmpty else {
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

    /// Parses one CSV record, including quoted fields and escaped quotes.
    private func parseCSVRow(_ row: String) -> [String]? {
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
    private func findOrCreateApp(appStoreId: String) -> AppRecord {
        let descriptor = FetchDescriptor<AppRecord>(
            predicate: #Predicate { $0.appStoreId == appStoreId }
        )

        if let existingApp = try? modelContext.fetch(descriptor).first {
            return existingApp
        }

        // Create new app with placeholder name
        let newApp = AppRecord(name: "App \(appStoreId)", appStoreId: appStoreId)
        modelContext.insert(newApp)
        return newApp
    }
}
