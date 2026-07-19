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
        }
    }
}

struct CSVImportResult {
    let importedCount: Int
    let skippedDuplicates: Int
    let appStoreId: String
    let batchId: UUID
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
    func importCodes(from url: URL, batchName: String? = nil, expirationDate: Date? = nil) throws -> CSVImportResult {
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
            expirationDate: effectiveExpirationDate
        )
    }

    /// Imports codes from a CSV string (used by API imports)
    /// - Parameters:
    ///   - csvString: The CSV content as a string
    ///   - batchName: Name for the batch
    ///   - source: The import source (.csv or .api)
    ///   - expirationDate: Optional expiration date for all codes in this batch
    /// - Returns: Import result with statistics
    func importCodes(fromCSVString csvString: String, batchName: String, source: ImportSource = .csv, expirationDate: Date? = nil) throws -> CSVImportResult {
        // Parse CSV content
        let parsedCodes = try parseCSV(csvString)

        guard !parsedCodes.isEmpty else {
            throw CSVImportError.noValidCodes
        }

        // All codes should have the same App Store ID
        guard let appStoreId = parsedCodes.first?.appStoreId else {
            throw CSVImportError.noValidCodes
        }

        // Find or create the App
        let app = findOrCreateApp(appStoreId: appStoreId)

        // Create batch
        let batch = CodeBatch(name: batchName, source: source)
        batch.app = app
        batch.expirationDate = expirationDate
        modelContext.insert(batch)

        // Get existing codes for this app to detect duplicates
        let existingCodes = Set((app.codes ?? []).map { $0.code })

        // Import codes
        var importedCount = 0
        var skippedDuplicates = 0

        for parsed in parsedCodes {
            if existingCodes.contains(parsed.code) {
                skippedDuplicates += 1
                continue
            }

            let offerCode = OfferCode(code: parsed.code, redemptionURL: parsed.redemptionURL, expirationDate: expirationDate)
            offerCode.app = app
            offerCode.batch = batch
            modelContext.insert(offerCode)
            importedCount += 1
        }

        // Save changes
        try modelContext.save()

        return CSVImportResult(
            importedCount: importedCount,
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
    private func parseCSV(_ content: String) throws -> [ParsedCode] {
        var results: [ParsedCode] = []

        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for line in lines {
            // Split by comma
            let components = line.components(separatedBy: ",")

            guard components.count >= 2 else { continue }

            let code = components[0].trimmingCharacters(in: .whitespaces)
            let url = components[1].trimmingCharacters(in: .whitespaces)

            // Validate code format (18-char alphanumeric)
            guard isValidCode(code) else { continue }

            // Extract App Store ID from URL
            guard let appStoreId = extractAppStoreId(from: url) else { continue }

            results.append(ParsedCode(code: code, redemptionURL: url, appStoreId: appStoreId))
        }

        return results
    }

    /// Validates that the code is 18 characters alphanumeric
    private func isValidCode(_ code: String) -> Bool {
        let alphanumericSet = CharacterSet.alphanumerics
        return code.count == 18 && code.unicodeScalars.allSatisfy { alphanumericSet.contains($0) }
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
