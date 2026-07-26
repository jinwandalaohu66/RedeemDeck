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

    @MainActor
    private func makeInMemoryContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: AppRecord.self,
            CodeBatch.self,
            OfferCode.self,
            configurations: configuration
        )
    }

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

    @Test func promotionalCodeExpirationDefaultsToFourWeeksAfterIssueDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let issueDate = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 31
        )))

        let expirationDate = CSVImportDates.defaultExpirationDate(
            for: issueDate,
            codeKind: .promo,
            calendar: calendar
        )

        #expect(calendar.dateComponents(
            [.year, .month, .day],
            from: expirationDate
        ) == DateComponents(year: 2026, month: 9, day: 28))
    }

    @Test @MainActor
    func infersPromoAndOfferCodeKindsFromCSVContent() {
        #expect(CSVImportDates.inferCodeKind(from: "PROMO123") == .promo)
        #expect(CSVImportDates.inferCodeKind(from: "Promo Code\nPROMO123") == .promo)
        #expect(CSVImportDates.inferCodeKind(from: "Offer Code\nOFFER123") == .offer)
        #expect(CSVImportDates.inferCodeKind(
            from: "CODE123,https://apps.apple.com/redeem?ctx=offercodes&id=123&code=CODE123"
        ) == .offer)
        #expect(CSVImportDates.inferCodeKind(
            from: "Promo Code,Notes\nPROMO123,mention ctx=offercodes in documentation"
        ) == .promo)
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
    func editingABatchExpirationUpdatesEveryCode() throws {
        let container = try makeInMemoryContainer()
        let batch = CodeBatch(name: "Promo Codes", source: .csv)
        let firstCode = OfferCode(code: "FIRST", redemptionURL: "https://example.com/first")
        let secondCode = OfferCode(code: "SECOND", redemptionURL: "https://example.com/second")
        firstCode.batch = batch
        secondCode.batch = batch
        container.mainContext.insert(batch)
        container.mainContext.insert(firstCode)
        container.mainContext.insert(secondCode)
        let correctedExpirationDate = Date(timeIntervalSince1970: 1_800_000_000)

        batch.updateExpirationDate(correctedExpirationDate)

        #expect(batch.expirationDate == correctedExpirationDate)
        #expect((batch.codes ?? []).allSatisfy {
            $0.expirationDate == correctedExpirationDate
        })
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
        try "ABCDEFGHIJKLMNOPQR,https://apps.apple.com/redeem?ctx=offercodes&id=123&code=ABCDEFGHIJKLMNOPQR"
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

    @Test @MainActor
    func importedPromoDocumentDefaultsToFourWeeks() throws {
        let container = try makeInMemoryContainer()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let issueDate = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 5,
            day: 28
        )))
        var fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("csv")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try "Promo Code\nPROMO123"
            .write(to: fileURL, atomically: true, encoding: .utf8)
        var resourceValues = URLResourceValues()
        resourceValues.contentModificationDate = issueDate
        try fileURL.setResourceValues(resourceValues)
        let app = AppRecord(name: "Test App", appStoreId: "123")
        container.mainContext.insert(app)

        _ = try CSVImporter(modelContext: container.mainContext)
            .importCodes(from: fileURL, targetApp: app)

        let batches = try container.mainContext.fetch(FetchDescriptor<CodeBatch>())
        let codes = try container.mainContext.fetch(FetchDescriptor<OfferCode>())
        let currentCalendar = Calendar.current
        let expectedComponents = DateComponents(year: 2026, month: 6, day: 25)
        #expect(batches.first?.expirationDate.map {
            currentCalendar.dateComponents([.year, .month, .day], from: $0)
        } == expectedComponents)
        #expect(codes.first?.expirationDate.map {
            currentCalendar.dateComponents([.year, .month, .day], from: $0)
        } == expectedComponents)
    }

    @Test @MainActor
    func explicitExpirationOverridesTheInferredPromoDefault() throws {
        let container = try makeInMemoryContainer()
        let app = AppRecord(name: "Test App", appStoreId: "123")
        container.mainContext.insert(app)
        let confirmedExpirationDate = Date(timeIntervalSince1970: 1_800_000_000)

        _ = try CSVImporter(modelContext: container.mainContext).importCodes(
            fromCSVString: "Promo Code\nPROMO123",
            batchName: "Confirmed Promo",
            expirationDate: confirmedExpirationDate,
            targetApp: app
        )

        let batches = try container.mainContext.fetch(FetchDescriptor<CodeBatch>())
        let codes = try container.mainContext.fetch(FetchDescriptor<OfferCode>())
        #expect(batches.first?.expirationDate == confirmedExpirationDate)
        #expect(codes.first?.expirationDate == confirmedExpirationDate)
    }

    @Test @MainActor
    func apiOfferImportPreservesItsActualExpirationDate() throws {
        let container = try makeInMemoryContainer()
        let apiExpirationDate = Date(timeIntervalSince1970: 1_900_000_000)

        _ = try CSVImporter(modelContext: container.mainContext).importCodes(
            fromCSVString: "Offer Code,Redemption URL\nOFFER123,https://apps.apple.com/redeem?ctx=offercodes&id=123&code=OFFER123",
            batchName: "API Offer",
            source: .api,
            expirationDate: apiExpirationDate
        )

        let batches = try container.mainContext.fetch(FetchDescriptor<CodeBatch>())
        let codes = try container.mainContext.fetch(FetchDescriptor<OfferCode>())
        #expect(batches.first?.expirationDate == apiExpirationDate)
        #expect(codes.first?.expirationDate == apiExpirationDate)
    }

    @Test @MainActor
    func importsBOMHeaderAndQuotedCSVFields() throws {
        let container = try makeInMemoryContainer()
        let csv = """
        \u{FEFF}\"Code\",\"Redemption URL\",\"Notes\"
        \"A1\",\"https://apps.apple.com/redeem?ctx=offercodes&id=123&code=A1\",\"contains, comma\"
        """

        let result = try CSVImporter(modelContext: container.mainContext)
            .importCodes(fromCSVString: csv, batchName: "Quoted")

        let apps = try container.mainContext.fetch(FetchDescriptor<AppRecord>())
        let batches = try container.mainContext.fetch(FetchDescriptor<CodeBatch>())
        let codes = try container.mainContext.fetch(FetchDescriptor<OfferCode>())
        #expect(result.importedCount == 1)
        #expect(result.batchId != nil)
        #expect(apps.map(\.appStoreId) == ["123"])
        #expect(batches.map(\.name) == ["Quoted"])
        #expect(codes.map(\.code) == ["A1"])
    }

    @Test @MainActor
    func URLBearingImportUsesItsEmbeddedAppInsteadOfTheSelectedFallback() throws {
        let container = try makeInMemoryContainer()
        let selectedApp = AppRecord(name: "Selected App", appStoreId: "123")
        container.mainContext.insert(selectedApp)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("csv")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try "OFFER123,https://apps.apple.com/redeem?ctx=offercodes&id=999&code=OFFER123"
            .write(to: fileURL, atomically: true, encoding: .utf8)

        let result = try CSVImporter(modelContext: container.mainContext)
            .importCodes(from: fileURL, targetApp: selectedApp)

        let codes = try container.mainContext.fetch(FetchDescriptor<OfferCode>())
        #expect(result.appStoreId == "999")
        #expect(codes.first?.app?.appStoreId == "999")
        #expect((selectedApp.codes ?? []).isEmpty)
    }

    @Test @MainActor
    func importsCodeOnlyTextIntoExplicitTargetApp() throws {
        let container = try makeInMemoryContainer()
        let app = AppRecord(name: "Test App", appStoreId: "456")
        container.mainContext.insert(app)
        try container.mainContext.save()
        let sixtyFourCharacterCode = String(repeating: "A", count: 64)

        let result = try CSVImporter(modelContext: container.mainContext)
            .importCodes(
                fromCSVString: "SHORT12\r\n\(sixtyFourCharacterCode)\r\n",
                batchName: "Promo Codes",
                targetApp: app
            )

        let codes = try container.mainContext.fetch(
            FetchDescriptor<OfferCode>(sortBy: [SortDescriptor(\.code)])
        )
        #expect(result.importedCount == 2)
        #expect(codes.map(\.code) == [sixtyFourCharacterCode, "SHORT12"])
        #expect(codes.allSatisfy { code in
            code.redemptionURL.contains("id=456") &&
                code.redemptionURL.contains("code=\(code.code)")
        })
    }

    @Test @MainActor
    func codeOnlyTextRequiresATargetApp() throws {
        let container = try makeInMemoryContainer()

        do {
            _ = try CSVImporter(modelContext: container.mainContext)
                .importCodes(fromCSVString: "PROMO123", batchName: "Promo")
            Issue.record("Expected a target-app error")
        } catch CSVImportError.targetAppRequired {
            // Expected.
        }

        #expect(try container.mainContext.fetch(FetchDescriptor<AppRecord>()).isEmpty)
        #expect(try container.mainContext.fetch(FetchDescriptor<CodeBatch>()).isEmpty)
        #expect(try container.mainContext.fetch(FetchDescriptor<OfferCode>()).isEmpty)
    }

    @Test @MainActor
    func deduplicatesStoredAndRepeatedCodesWithoutCreatingAnEmptyBatch() throws {
        let container = try makeInMemoryContainer()
        let importer = CSVImporter(modelContext: container.mainContext)
        let url = "https://apps.apple.com/redeem?id=789&code=DUPLICATE1"
        let csv = "DUPLICATE1,\(url)\nDUPLICATE1,\(url)"

        let firstResult = try importer.importCodes(
            fromCSVString: csv,
            batchName: "First"
        )
        let secondResult = try importer.importCodes(
            fromCSVString: csv,
            batchName: "Second"
        )

        let batches = try container.mainContext.fetch(FetchDescriptor<CodeBatch>())
        let codes = try container.mainContext.fetch(FetchDescriptor<OfferCode>())
        #expect(firstResult.importedCount == 1)
        #expect(firstResult.skippedDuplicates == 1)
        #expect(secondResult.importedCount == 0)
        #expect(secondResult.skippedDuplicates == 2)
        #expect(secondResult.batchId == nil)
        #expect(batches.count == 1)
        #expect(codes.count == 1)
    }

    @Test @MainActor
    func rejectsMixedAppStoreIDsWithoutInsertingAnything() throws {
        let container = try makeInMemoryContainer()
        let csv = """
        FIRST1,https://apps.apple.com/redeem?id=111&code=FIRST1
        SECOND2,https://apps.apple.com/redeem?id=222&code=SECOND2
        """

        do {
            _ = try CSVImporter(modelContext: container.mainContext)
                .importCodes(fromCSVString: csv, batchName: "Mixed")
            Issue.record("Expected an app-ID mismatch error")
        } catch CSVImportError.appStoreIdMismatch {
            // Expected.
        }

        #expect(try container.mainContext.fetch(FetchDescriptor<AppRecord>()).isEmpty)
        #expect(try container.mainContext.fetch(FetchDescriptor<CodeBatch>()).isEmpty)
        #expect(try container.mainContext.fetch(FetchDescriptor<OfferCode>()).isEmpty)
    }

    @Test @MainActor
    func importedCodesPersistAfterReopeningOnDiskStore() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("codes.store")

        do {
            let configuration = ModelConfiguration(url: storeURL)
            let container = try ModelContainer(
                for: AppRecord.self,
                CodeBatch.self,
                OfferCode.self,
                configurations: configuration
            )
            _ = try CSVImporter(modelContext: container.mainContext)
                .importCodes(
                    fromCSVString: "PERSIST1,https://apps.apple.com/redeem?id=999&code=PERSIST1",
                    batchName: "Persistent"
                )
        }

        let reopenedConfiguration = ModelConfiguration(url: storeURL)
        let reopenedContainer = try ModelContainer(
            for: AppRecord.self,
            CodeBatch.self,
            OfferCode.self,
            configurations: reopenedConfiguration
        )
        let apps = try reopenedContainer.mainContext.fetch(FetchDescriptor<AppRecord>())
        let batches = try reopenedContainer.mainContext.fetch(FetchDescriptor<CodeBatch>())
        let codes = try reopenedContainer.mainContext.fetch(FetchDescriptor<OfferCode>())
        #expect(apps.map(\.appStoreId) == ["999"])
        #expect(batches.map(\.name) == ["Persistent"])
        #expect(codes.map(\.code) == ["PERSIST1"])
        #expect(codes.first?.app?.appStoreId == "999")
        #expect(codes.first?.batch?.name == "Persistent")
    }

}
