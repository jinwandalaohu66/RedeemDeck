//
//  AppStoreCodesTests.swift
//  AppStoreCodesTests
//
//  Created by Matteo Comisso on 08/12/2025.
//

import Foundation
import SwiftData
import Testing
@testable import CodeVault

struct AppStoreCodesTests {

    @Test func expirationDefaultsToSixCalendarMonthsAfterIssueDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let issueDate = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 31
        )))

        let expirationDate = CSVImportDates.defaultExpirationDate(
            for: issueDate,
            calendar: calendar
        )

        #expect(calendar.dateComponents(
            [.year, .month, .day],
            from: expirationDate
        ) == DateComponents(year: 2027, month: 2, day: 28))
    }

    @Test @MainActor
    func backfillsExistingCSVBatchAndCodeExpirationDates() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: AppRecord.self,
            CodeBatch.self,
            OfferCode.self,
            configurations: configuration
        )
        let context = container.mainContext
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let issueDate = try #require(calendar.date(from: DateComponents(
            year: 2025,
            month: 12,
            day: 8
        )))
        let expectedExpirationDate = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 6,
            day: 8
        )))
        let batch = CodeBatch(name: "Legacy CSV", source: .csv)
        batch.importDate = issueDate
        let code = OfferCode(
            code: "ABCDEFGHIJKLMNOPQR",
            redemptionURL: "https://apps.apple.com/redeem?id=123&code=ABCDEFGHIJKLMNOPQR"
        )
        code.batch = batch
        context.insert(batch)
        context.insert(code)

        let updatedCount = try CSVImporter(modelContext: context)
            .backfillMissingCSVExpirationDates(calendar: calendar)

        #expect(updatedCount == 1)
        #expect(batch.expirationDate == expectedExpirationDate)
        #expect(code.expirationDate == expectedExpirationDate)

        let secondUpdatedCount = try CSVImporter(modelContext: context)
            .backfillMissingCSVExpirationDates(calendar: calendar)
        #expect(secondUpdatedCount == 0)
    }

    @Test @MainActor
    func importedDocumentDefaultsExpirationFromItsModificationDate() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: AppRecord.self,
            CodeBatch.self,
            OfferCode.self,
            configurations: configuration
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let issueDate = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 5,
            day: 28
        )))
        let expectedExpirationDate = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 11,
            day: 28
        )))
        var fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("csv")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try "ABCDEFGHIJKLMNOPQR,https://apps.apple.com/redeem?id=123&code=ABCDEFGHIJKLMNOPQR"
            .write(to: fileURL, atomically: true, encoding: .utf8)
        var resourceValues = URLResourceValues()
        resourceValues.contentModificationDate = issueDate
        try fileURL.setResourceValues(resourceValues)

        _ = try CSVImporter(modelContext: container.mainContext)
            .importCodes(from: fileURL)

        let batches = try container.mainContext.fetch(FetchDescriptor<CodeBatch>())
        let codes = try container.mainContext.fetch(FetchDescriptor<OfferCode>())
        #expect(batches.count == 1)
        #expect(codes.count == 1)
        #expect(batches.first?.expirationDate == expectedExpirationDate)
        #expect(codes.first?.expirationDate == expectedExpirationDate)
    }

}
