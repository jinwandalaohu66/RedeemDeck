import Foundation
import SwiftData
import Testing
@testable import CodeVault

struct BackupRepositoryTests {
    @Test @MainActor
    func roundTripRestoresCategoryRelationshipsAndMergesByID() async throws {
        let source = try TestModelStore.makeInMemoryContainer()
        let app = AppRecord(name: "Example", appStoreId: "123")
        app.qrGreeting = "Have a wonderful day!"
        let category = CodeCategory(
            name: "50% Off",
            productName: "Pro Monthly",
            app: app
        )
        let batch = CodeBatch(name: "September Import", source: .csv)
        batch.app = app
        batch.category = category
        let code = OfferCode(code: "BACKUP1", redemptionURL: "https://example.com")
        code.app = app
        code.batch = batch
        let retrievalID = UUID()
        code.reserve(for: retrievalID)
        source.mainContext.insert(app)
        source.mainContext.insert(category)
        source.mainContext.insert(batch)
        source.mainContext.insert(code)
        try source.mainContext.save()

        let archive = try await BackupRepository(modelContainer: source).makeArchive()
        let data = try await BackupCodec.shared.encode(archive)
        let decoded = try await BackupCodec.shared.decode(data)
        let destination = try TestModelStore.makeInMemoryContainer()
        let repository = BackupRepository(modelContainer: destination)

        let first = try await repository.restore(decoded)
        let second = try await repository.restore(decoded)

        #expect(first.apps == 1)
        #expect(first.categories == 1)
        #expect(first.codes == 1)
        #expect(second.codes == 1)
        #expect(try destination.mainContext.fetch(FetchDescriptor<AppRecord>()).count == 1)
        #expect(try destination.mainContext.fetch(FetchDescriptor<CodeCategory>()).count == 1)
        let restoredCode = try #require(destination.mainContext
            .fetch(FetchDescriptor<OfferCode>()).first)
        #expect(restoredCode.batch?.category?.name == "50% Off")
        #expect(restoredCode.batch?.category?.productName == "Pro Monthly")
        #expect(restoredCode.retrievalID == retrievalID)
        #expect(restoredCode.lifecycleStatus == .pending)
        let restoredApp = try #require(destination.mainContext
            .fetch(FetchDescriptor<AppRecord>()).first)
        #expect(restoredApp.qrGreeting == "Have a wonderful day!")
    }

    @Test @MainActor
    func restoreBuildsCategoriesForSchemaOneBackups() async throws {
        let source = try TestModelStore.makeInMemoryContainer()
        let app = AppRecord(name: "Legacy", appStoreId: "456")
        let batch = CodeBatch(name: "Launch Codes", source: .csv)
        batch.app = app
        batch.productID = "pro.monthly"
        batch.offerReferenceName = "launch-half-off"
        let code = OfferCode(code: "LEGACY1", redemptionURL: "https://example.com")
        code.app = app
        code.batch = batch
        source.mainContext.insert(app)
        source.mainContext.insert(batch)
        source.mainContext.insert(code)
        try source.mainContext.save()

        let current = try await BackupRepository(modelContainer: source).makeArchive()
        let legacy = CodeVaultBackupArchive(
            schemaVersion: 1,
            createdAt: current.createdAt,
            apps: current.apps,
            categories: nil,
            batches: current.batches,
            codes: current.codes,
            campaigns: current.campaigns,
            recipients: current.recipients,
            distributions: current.distributions,
            activities: current.activities,
            templates: current.templates
        )
        let destination = try TestModelStore.makeInMemoryContainer()
        let summary = try await BackupRepository(modelContainer: destination).restore(legacy)

        #expect(summary.categories == 1)
        let restoredBatch = try #require(destination.mainContext
            .fetch(FetchDescriptor<CodeBatch>()).first)
        #expect(restoredBatch.category?.productName == "pro.monthly")
        #expect(restoredBatch.category?.name == "launch-half-off")
    }

    @Test
    func codecRejectsUnsupportedSchema() async throws {
        let archive = CodeVaultBackupArchive(
            schemaVersion: 999,
            createdAt: Date(),
            apps: [],
            categories: [],
            batches: [],
            codes: [],
            campaigns: [],
            recipients: [],
            distributions: [],
            activities: [],
            templates: []
        )
        let data = try await BackupCodec.shared.encode(archive)

        do {
            _ = try await BackupCodec.shared.decode(data)
            Issue.record("Expected unsupported schema")
        } catch BackupCodecError.unsupportedVersion {
            // Expected behavior.
        }
    }
}
