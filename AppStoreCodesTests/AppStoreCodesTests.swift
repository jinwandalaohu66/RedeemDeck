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
    func backfillsExistingCSVBatchAndCodeExpirationDates() async throws {
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
        try context.save()
        let importer = CSVImporter(modelContainer: container)

        let updatedCount = try await importer
            .backfillMissingCSVExpirationDates(calendar: calendar)

        let updatedBatch = try #require(
            context.fetch(FetchDescriptor<CodeBatch>()).first
        )
        let updatedCode = try #require(
            context.fetch(FetchDescriptor<OfferCode>()).first
        )

        #expect(updatedCount == 1)
        #expect(updatedBatch.expirationDate == expectedExpirationDate)
        #expect(updatedCode.expirationDate == expectedExpirationDate)

        let secondUpdatedCount = try await importer
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
    func importedDocumentDefaultsExpirationFromItsModificationDate() async throws {
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

        _ = try await CSVImporter(modelContainer: container)
            .importCodes(from: fileURL)

        let batches = try container.mainContext.fetch(FetchDescriptor<CodeBatch>())
        let codes = try container.mainContext.fetch(FetchDescriptor<OfferCode>())
        #expect(batches.count == 1)
        #expect(codes.count == 1)
        #expect(batches.first?.expirationDate == expectedExpirationDate)
        #expect(codes.first?.expirationDate == expectedExpirationDate)
    }

    @Test @MainActor
    func importedPromoDocumentDefaultsToFourWeeks() async throws {
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
        try container.mainContext.save()

        _ = try await CSVImporter(modelContainer: container)
            .importCodes(from: fileURL, targetAppStoreId: app.appStoreId)

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
    func explicitExpirationOverridesTheInferredPromoDefault() async throws {
        let container = try makeInMemoryContainer()
        let app = AppRecord(name: "Test App", appStoreId: "123")
        container.mainContext.insert(app)
        try container.mainContext.save()
        let confirmedExpirationDate = Date(timeIntervalSince1970: 1_800_000_000)

        _ = try await CSVImporter(modelContainer: container).importCodes(
            fromCSVString: "Promo Code\nPROMO123",
            batchName: "Confirmed Promo",
            expirationDate: confirmedExpirationDate,
            targetAppStoreId: app.appStoreId
        )

        let batches = try container.mainContext.fetch(FetchDescriptor<CodeBatch>())
        let codes = try container.mainContext.fetch(FetchDescriptor<OfferCode>())
        #expect(batches.first?.expirationDate == confirmedExpirationDate)
        #expect(codes.first?.expirationDate == confirmedExpirationDate)
    }

    @Test @MainActor
    func apiOfferImportPreservesItsActualExpirationDate() async throws {
        let container = try makeInMemoryContainer()
        let apiExpirationDate = Date(timeIntervalSince1970: 1_900_000_000)

        _ = try await CSVImporter(modelContainer: container).importCodes(
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

    @Test
    func sentCodeIsUnavailableWithoutBeingRedeemed() {
        let code = OfferCode(code: "AUDIT1", redemptionURL: "https://example.com/AUDIT1")
        let sentAt = Date(timeIntervalSince1970: 1_800_000_000)

        #expect(code.isAvailable)

        code.markAsSent(
            at: sentAt,
            assignedTo: "Taylor",
            notes: "Launch post in #announcements"
        )

        #expect(!code.isAvailable)
        #expect(code.sentAt == sentAt)
        #expect(code.assignedTo == "Taylor")
        #expect(code.notes == "Launch post in #announcements")
        #expect(!code.isRedeemed)
        #expect(code.redeemedDate == nil)
    }

    @Test
    func redemptionKeepsTheSentAuditEventDistinct() {
        let code = OfferCode(code: "AUDIT2", redemptionURL: "https://example.com/AUDIT2")
        let sentAt = Date(timeIntervalSince1970: 1_800_000_000)
        code.markAsSent(at: sentAt, assignedTo: "Morgan")

        code.markAsRedeemed()

        #expect(code.sentAt == sentAt)
        #expect(code.isRedeemed)
        #expect(code.redeemedDate != nil)
        #expect(!code.isAvailable)
    }

    @Test
    func markingCodeUnsentPreservesRedemption() {
        let code = OfferCode(code: "AUDIT3", redemptionURL: "https://example.com/AUDIT3")
        code.markAsSent(at: Date(timeIntervalSince1970: 1_800_000_000))
        code.markAsRedeemed()
        let redeemedDate = code.redeemedDate

        code.markAsUnsent()

        #expect(code.sentAt == nil)
        #expect(code.isRedeemed)
        #expect(code.redeemedDate == redeemedDate)
        #expect(!code.isAvailable)
    }

    @Test
    func markingCodeUnredeemedPreservesSentAuditEvent() {
        let code = OfferCode(code: "AUDIT4", redemptionURL: "https://example.com/AUDIT4")
        let sentAt = Date(timeIntervalSince1970: 1_800_000_000)
        code.markAsSent(at: sentAt)
        code.markAsRedeemed()

        code.markAsUnredeemed()

        #expect(!code.isRedeemed)
        #expect(code.redeemedDate == nil)
        #expect(code.sentAt == sentAt)
        #expect(!code.isAvailable)
    }

    @Test
    func makingCodeAvailableClearsLifecycleDates() {
        let code = OfferCode(code: "AUDIT5", redemptionURL: "https://example.com/AUDIT5")
        code.markAsSent(at: Date(timeIntervalSince1970: 1_800_000_000))
        code.markAsRedeemed()

        code.markAsAvailable()

        #expect(code.sentAt == nil)
        #expect(code.redeemedDate == nil)
        #expect(!code.isRedeemed)
        #expect(code.isAvailable)
    }

    @Test
    func sentCodesAreExcludedFromAppAndBatchAvailabilityCounts() {
        let app = AppRecord(name: "Audit App", appStoreId: "123")
        let batch = CodeBatch(name: "Launch", source: .csv)
        let availableCode = OfferCode(code: "AVAILABLE", redemptionURL: "https://example.com/available")
        let sentCode = OfferCode(code: "SENT", redemptionURL: "https://example.com/sent")
        availableCode.app = app
        availableCode.batch = batch
        sentCode.app = app
        sentCode.batch = batch
        sentCode.markAsSent()

        #expect(app.availableCodesCount == 1)
        #expect(batch.availableCodesCount == 1)
    }

    @Test @MainActor
    func importsBOMHeaderAndQuotedCSVFields() async throws {
        let container = try makeInMemoryContainer()
        let csv = """
        \u{FEFF}\"Code\",\"Redemption URL\",\"Notes\"
        \"A1\",\"https://apps.apple.com/redeem?ctx=offercodes&id=123&code=A1\",\"contains, comma\"
        """

        let result = try await CSVImporter(modelContainer: container)
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
    func URLBearingImportUsesItsEmbeddedAppInsteadOfTheSelectedFallback() async throws {
        let container = try makeInMemoryContainer()
        let selectedApp = AppRecord(name: "Selected App", appStoreId: "123")
        container.mainContext.insert(selectedApp)
        try container.mainContext.save()
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("csv")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try "OFFER123,https://apps.apple.com/redeem?ctx=offercodes&id=999&code=OFFER123"
            .write(to: fileURL, atomically: true, encoding: .utf8)

        let result = try await CSVImporter(modelContainer: container)
            .importCodes(from: fileURL, targetAppStoreId: selectedApp.appStoreId)

        let codes = try container.mainContext.fetch(FetchDescriptor<OfferCode>())
        #expect(result.appStoreId == "999")
        #expect(codes.first?.app?.appStoreId == "999")
        #expect((selectedApp.codes ?? []).isEmpty)
    }

    @Test @MainActor
    func importsCodeOnlyTextIntoExplicitTargetApp() async throws {
        let container = try makeInMemoryContainer()
        let app = AppRecord(name: "Test App", appStoreId: "456")
        container.mainContext.insert(app)
        try container.mainContext.save()
        let sixtyFourCharacterCode = String(repeating: "A", count: 64)

        let result = try await CSVImporter(modelContainer: container)
            .importCodes(
                fromCSVString: "SHORT12\r\n\(sixtyFourCharacterCode)\r\n",
                batchName: "Promo Codes",
                targetAppStoreId: app.appStoreId
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
    func codeOnlyTextRequiresATargetApp() async throws {
        let container = try makeInMemoryContainer()

        do {
            _ = try await CSVImporter(modelContainer: container)
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
    func deduplicatesStoredAndRepeatedCodesWithoutCreatingAnEmptyBatch() async throws {
        let container = try makeInMemoryContainer()
        let importer = CSVImporter(modelContainer: container)
        let url = "https://apps.apple.com/redeem?id=789&code=DUPLICATE1"
        let csv = "DUPLICATE1,\(url)\nDUPLICATE1,\(url)"

        let firstResult = try await importer.importCodes(
            fromCSVString: csv,
            batchName: "First"
        )
        let secondResult = try await importer.importCodes(
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
    func serializesConcurrentImportsThroughOneImporter() async throws {
        let container = try makeInMemoryContainer()
        let importer = CSVImporter(modelContainer: container)
        let csv = "RACE1,https://apps.apple.com/redeem?id=789&code=RACE1"

        async let first = importer.importCodes(
            fromCSVString: csv,
            batchName: "First"
        )
        async let second = importer.importCodes(
            fromCSVString: csv,
            batchName: "Second"
        )
        let results = try await [first, second]

        let batches = try container.mainContext.fetch(FetchDescriptor<CodeBatch>())
        let codes = try container.mainContext.fetch(FetchDescriptor<OfferCode>())
        #expect(results.map(\.importedCount).reduce(0, +) == 1)
        #expect(results.map(\.skippedDuplicates).reduce(0, +) == 1)
        #expect(batches.count == 1)
        #expect(codes.map(\.code) == ["RACE1"])
    }

    @Test @MainActor
    func rollsBackFailedImportBeforeReusingLongLivedContext() async throws {
        let container = try makeInMemoryContainer()
        let importer = CSVImporter(modelContainer: container)
        await importer.failBeforeNextSaveForTesting()

        do {
            _ = try await importer.importCodes(
                fromCSVString: "ROLLBACK1,https://apps.apple.com/redeem?id=321&code=ROLLBACK1",
                batchName: "Failed"
            )
            Issue.record("Expected a forced pre-save failure")
        } catch CSVImporterTestError.forcedFailure {
            // Expected.
        }

        #expect(try container.mainContext.fetch(FetchDescriptor<AppRecord>()).isEmpty)
        #expect(try container.mainContext.fetch(FetchDescriptor<CodeBatch>()).isEmpty)
        #expect(try container.mainContext.fetch(FetchDescriptor<OfferCode>()).isEmpty)

        let result = try await importer.importCodes(
            fromCSVString: "RECOVERED1,https://apps.apple.com/redeem?id=654&code=RECOVERED1",
            batchName: "Recovered"
        )
        #expect(result.importedCount == 1)
        #expect(try container.mainContext.fetch(FetchDescriptor<AppRecord>()).map(\.appStoreId) == ["654"])
        #expect(try container.mainContext.fetch(FetchDescriptor<CodeBatch>()).map(\.name) == ["Recovered"])
        #expect(try container.mainContext.fetch(FetchDescriptor<OfferCode>()).map(\.code) == ["RECOVERED1"])
    }

    @Test @MainActor
    func inspectsCSVFileAsynchronouslyWithoutChangingTheStore() async throws {
        let container = try makeInMemoryContainer()
        let importer = CSVImporter(modelContainer: container)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("csv")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try "Promo Code\nPROMO123".write(to: fileURL, atomically: true, encoding: .utf8)

        let inspection = try await importer.inspect(fileURL)

        #expect(inspection.codeKind == .promo)
        #expect(inspection.expirationDate > inspection.issueDate)
        #expect(try container.mainContext.fetch(FetchDescriptor<AppRecord>()).isEmpty)
        #expect(try container.mainContext.fetch(FetchDescriptor<CodeBatch>()).isEmpty)
        #expect(try container.mainContext.fetch(FetchDescriptor<OfferCode>()).isEmpty)
    }

    @Test @MainActor
    func rejectsMixedAppStoreIDsWithoutInsertingAnything() async throws {
        let container = try makeInMemoryContainer()
        let csv = """
        FIRST1,https://apps.apple.com/redeem?id=111&code=FIRST1
        SECOND2,https://apps.apple.com/redeem?id=222&code=SECOND2
        """

        do {
            _ = try await CSVImporter(modelContainer: container)
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
    func importedCodesPersistAfterReopeningOnDiskStore() async throws {
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
            _ = try await CSVImporter(modelContainer: container)
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

    @Test @MainActor
    func sentAuditMetadataPersistsAfterReopeningOnDiskStore() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("codes.store")
        let sentAt = Date(timeIntervalSince1970: 1_800_000_000)

        do {
            let configuration = ModelConfiguration(url: storeURL)
            let container = try ModelContainer(
                for: AppRecord.self,
                CodeBatch.self,
                OfferCode.self,
                configurations: configuration
            )
            let code = OfferCode(
                code: "AUDIT-PERSIST",
                redemptionURL: "https://example.com/AUDIT-PERSIST"
            )
            code.markAsSent(
                at: sentAt,
                assignedTo: "Jamie",
                notes: "Creator campaign on Mastodon"
            )
            container.mainContext.insert(code)
            try container.mainContext.save()
        }

        let configuration = ModelConfiguration(url: storeURL)
        let container = try ModelContainer(
            for: AppRecord.self,
            CodeBatch.self,
            OfferCode.self,
            configurations: configuration
        )
        let code = try #require(
            container.mainContext.fetch(FetchDescriptor<OfferCode>()).first
        )
        #expect(code.sentAt == sentAt)
        #expect(code.assignedTo == "Jamie")
        #expect(code.notes == "Creator campaign on Mastodon")
        #expect(!code.isRedeemed)
        #expect(code.redeemedDate == nil)
        #expect(!code.isAvailable)
    }

}
