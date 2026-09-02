import Foundation
import SwiftData
import Testing
@testable import CodeVault

struct CSVImporterTests {
    @Test @MainActor
    func importsQuotedFieldsAndConfiguredMetadata() async throws {
        let container = try TestModelStore.makeInMemoryContainer()
        let app = AppRecord(name: "Example", appStoreId: "123")
        let category = CodeCategory(name: "Half Off", productName: "Pro Monthly", app: app)
        container.mainContext.insert(app)
        container.mainContext.insert(category)
        try container.mainContext.save()
        let csv = """
        \u{FEFF}"Code","Redemption URL","Notes"
        "A1","https://apps.apple.com/redeem?ctx=offercodes&id=123&code=A1","contains, comma"
        """

        let result = try await CSVImporter(modelContainer: container).importCodes(
            fromCSVString: csv,
            batchName: "Launch Codes",
            targetAppStoreId: "123",
            codeKind: .oneTimeOffer,
            environment: .sandbox,
            platform: .iPadOS,
            appVersion: "2.0",
            category: .existing(category.id)
        )

        let batch = try #require(container.mainContext
            .fetch(FetchDescriptor<CodeBatch>()).first)
        let code = try #require(container.mainContext
            .fetch(FetchDescriptor<OfferCode>()).first)
        #expect(result.importedCount == 1)
        #expect(batch.codeKind == .oneTimeOffer)
        #expect(batch.environment == .sandbox)
        #expect(batch.platform == .iPadOS)
        #expect(batch.appVersion == "2.0")
        #expect(batch.category?.id == category.id)
        #expect(code.code == "A1")
    }

    @Test @MainActor
    func importsCodeOnlyRowsIntoSelectedApp() async throws {
        let container = try TestModelStore.makeInMemoryContainer()
        let app = AppRecord(name: "Example", appStoreId: "456")
        container.mainContext.insert(app)
        try container.mainContext.save()
        let longCode = String(repeating: "A", count: 64)

        let result = try await CSVImporter(modelContainer: container).importCodes(
            fromCSVString: "SHORT12\r\n\(longCode)\r\n",
            batchName: "Promo",
            targetAppStoreId: "456"
        )

        let codes = try container.mainContext.fetch(
            FetchDescriptor<OfferCode>(sortBy: [SortDescriptor(\.code)])
        )
        #expect(result.importedCount == 2)
        #expect(codes.map(\.code) == [longCode, "SHORT12"])
        #expect(codes.allSatisfy { $0.redemptionURL.contains("id=456") })
    }

    @Test @MainActor
    func codeOnlyRowsRequireSelectedApp() async throws {
        let container = try TestModelStore.makeInMemoryContainer()

        do {
            _ = try await CSVImporter(modelContainer: container).importCodes(
                fromCSVString: "PROMO123",
                batchName: "Promo"
            )
            Issue.record("Expected target-app validation")
        } catch CSVImportError.targetAppRequired {
            // Expected behavior.
        }

        #expect(try container.mainContext.fetch(FetchDescriptor<AppRecord>()).isEmpty)
        #expect(try container.mainContext.fetch(FetchDescriptor<OfferCode>()).isEmpty)
    }

    @Test @MainActor
    func rejectsMultipleAppStoreIDsAtomically() async throws {
        let container = try TestModelStore.makeInMemoryContainer()
        let csv = """
        FIRST1,https://apps.apple.com/redeem?id=111&code=FIRST1
        SECOND2,https://apps.apple.com/redeem?id=222&code=SECOND2
        """

        do {
            _ = try await CSVImporter(modelContainer: container).importCodes(
                fromCSVString: csv,
                batchName: "Mixed"
            )
            Issue.record("Expected app-ID validation")
        } catch CSVImportError.appStoreIdMismatch {
            // Expected behavior.
        }

        #expect(try container.mainContext.fetch(FetchDescriptor<AppRecord>()).isEmpty)
        #expect(try container.mainContext.fetch(FetchDescriptor<CodeBatch>()).isEmpty)
        #expect(try container.mainContext.fetch(FetchDescriptor<OfferCode>()).isEmpty)
    }

    @Test @MainActor
    func skipsStoredAndRepeatedDuplicatesWithoutEmptyBatch() async throws {
        let container = try TestModelStore.makeInMemoryContainer()
        let importer = CSVImporter(modelContainer: container)
        let url = "https://apps.apple.com/redeem?id=789&code=DUPLICATE1"
        let csv = "DUPLICATE1,\(url)\nDUPLICATE1,\(url)"

        let first = try await importer.importCodes(
            fromCSVString: csv,
            batchName: "First"
        )
        let second = try await importer.importCodes(
            fromCSVString: csv,
            batchName: "Second"
        )

        #expect(first.importedCount == 1)
        #expect(first.skippedDuplicates == 1)
        #expect(second.importedCount == 0)
        #expect(second.batchId == nil)
        #expect(try container.mainContext.fetch(FetchDescriptor<CodeBatch>()).count == 1)
    }

    @Test @MainActor
    func serializesConcurrentImports() async throws {
        let container = try TestModelStore.makeInMemoryContainer()
        let importer = CSVImporter(modelContainer: container)
        let csv = "RACE1,https://apps.apple.com/redeem?id=789&code=RACE1"

        async let first = importer.importCodes(fromCSVString: csv, batchName: "First")
        async let second = importer.importCodes(fromCSVString: csv, batchName: "Second")
        let results = try await [first, second]

        #expect(results.map(\.importedCount).reduce(0, +) == 1)
        #expect(results.map(\.skippedDuplicates).reduce(0, +) == 1)
        #expect(try container.mainContext.fetch(FetchDescriptor<OfferCode>()).count == 1)
    }

    @Test @MainActor
    func rollsBackFailureBeforeContextReuse() async throws {
        let container = try TestModelStore.makeInMemoryContainer()
        let importer = CSVImporter(modelContainer: container)
        await importer.failBeforeNextSaveForTesting()

        do {
            _ = try await importer.importCodes(
                fromCSVString: "FAIL1,https://apps.apple.com/redeem?id=321&code=FAIL1",
                batchName: "Failed"
            )
            Issue.record("Expected forced failure")
        } catch CSVImporterTestError.forcedFailure {
            // Expected behavior.
        }

        let recovered = try await importer.importCodes(
            fromCSVString: "OK1,https://apps.apple.com/redeem?id=654&code=OK1",
            batchName: "Recovered"
        )
        #expect(recovered.importedCount == 1)
        #expect(try container.mainContext.fetch(FetchDescriptor<AppRecord>())
            .map(\.appStoreId) == ["654"])
    }
}
