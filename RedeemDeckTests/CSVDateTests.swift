import Foundation
import SwiftData
import Testing
@testable import RedeemDeck

struct CSVDateTests {
    @Test
    func offerExpirationUsesSixCalendarMonths() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let issueDate = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 31
        )))

        let expiration = CSVImportDates.defaultExpirationDate(
            for: issueDate,
            calendar: calendar
        )

        #expect(calendar.dateComponents([.year, .month, .day], from: expiration)
            == DateComponents(year: 2027, month: 2, day: 28))
    }

    @Test
    func promoExpirationUsesFourWeeks() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let issueDate = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 31
        )))

        let expiration = CSVImportDates.defaultExpirationDate(
            for: issueDate,
            codeKind: .promo,
            calendar: calendar
        )

        #expect(calendar.dateComponents([.year, .month, .day], from: expiration)
            == DateComponents(year: 2026, month: 9, day: 28))
    }

    @Test
    func infersKindsFromHeadersAndRedemptionURLs() {
        #expect(CSVImportDates.inferCodeKind(from: "Promo Code\nPROMO123") == .promo)
        #expect(CSVImportDates.inferCodeKind(from: "Offer Code\nOFFER123") == .offer)
        #expect(CSVImportDates.inferCodeKind(
            from: "CODE123,https://apps.apple.com/redeem?ctx=offercodes&id=123&code=CODE123"
        ) == .offer)
        #expect(CSVImportDates.inferCodeKind(
            from: "Promo Code,Notes\nPROMO123,ctx=offercodes"
        ) == .promo)
    }

    @Test @MainActor
    func backfillsLegacyCSVExpirationOnlyOnce() async throws {
        let container = try TestModelStore.makeInMemoryContainer()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let issueDate = try #require(calendar.date(from: DateComponents(
            year: 2025, month: 12, day: 8
        )))
        let expected = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 6, day: 8
        )))
        let batch = CodeBatch(name: "Legacy CSV", source: .csv)
        batch.importDate = issueDate
        let code = OfferCode(code: "LEGACY123", redemptionURL: "https://example.com")
        code.batch = batch
        container.mainContext.insert(batch)
        container.mainContext.insert(code)
        try container.mainContext.save()
        let importer = CSVImporter(modelContainer: container)

        let firstCount = try await importer
            .backfillMissingCSVExpirationDates(calendar: calendar)
        let secondCount = try await importer
            .backfillMissingCSVExpirationDates(calendar: calendar)
        let verificationContext = ModelContext(container)
        let updatedBatch = try #require(verificationContext.fetch(
            FetchDescriptor<CodeBatch>()
        ).first)
        let updatedCode = try #require(verificationContext.fetch(
            FetchDescriptor<OfferCode>()
        ).first)

        #expect(firstCount == 1)
        #expect(secondCount == 0)
        #expect(updatedBatch.expirationDate == expected)
        #expect(updatedCode.expirationDate == expected)
    }

    @Test @MainActor
    func editingBatchExpirationUpdatesCodes() throws {
        let batch = CodeBatch(name: "Promo", source: .csv)
        let first = OfferCode(code: "FIRST", redemptionURL: "https://example.com/1")
        let second = OfferCode(code: "SECOND", redemptionURL: "https://example.com/2")
        first.batch = batch
        second.batch = batch
        let date = Date(timeIntervalSince1970: 1_800_000_000)

        batch.updateExpirationDate(date)

        #expect(batch.expirationDate == date)
        #expect((batch.codes ?? []).allSatisfy { $0.expirationDate == date })
    }
}
