import Foundation
import SwiftData
import Testing
@testable import CodeVault

struct CodeRetrievalRepositoryTests {
    @Test @MainActor
    func retrievalIsAllOrNothingWhenQuantityExceedsInventory() async throws {
        let fixture = try makeFixture(codeCount: 2)
        let repository = CodeVaultRepository(modelContainer: fixture.container)

        await #expect(throws: CodeVaultRepositoryError.self) {
            try await repository.reserveCodes(categoryID: fixture.categoryID, quantity: 3)
        }

        let codes = try fixture.container.mainContext.fetch(FetchDescriptor<OfferCode>())
        #expect(codes.allSatisfy { $0.isAvailable })
        #expect(codes.allSatisfy { $0.retrievalID == nil })
    }

    @Test @MainActor
    func pendingRetrievalSurvivesRepositoryRecreation() async throws {
        let fixture = try makeFixture(codeCount: 3)
        let firstRepository = CodeVaultRepository(modelContainer: fixture.container)
        let selection = try await firstRepository.reserveCodes(
            categoryID: fixture.categoryID,
            quantity: 2
        )

        let reopenedRepository = CodeVaultRepository(modelContainer: fixture.container)
        let pending = try await reopenedRepository.loadPendingSelections()
        let restored = try #require(try await reopenedRepository.loadSelection(id: selection.id))

        #expect(pending.map(\.id) == [selection.id])
        #expect(restored.codes.count == 2)
        #expect(restored.pendingCount == 2)
    }

    @Test @MainActor
    func migrationMakesAnOlderReservationResumable() async throws {
        let fixture = try makeFixture(codeCount: 1)
        let code = try #require(fixture.container.mainContext
            .fetch(FetchDescriptor<OfferCode>()).first)
        code.reservedAt = Date()
        code.retrievalID = nil
        try fixture.container.mainContext.save()

        try await CodeVaultMigrationService(modelContainer: fixture.container)
            .performAdditiveMigration()
        let pending = try await CodeVaultRepository(modelContainer: fixture.container)
            .loadPendingSelections()

        let selection = try #require(pending.first)
        #expect(pending.count == 1)
        #expect(selection.codes.map(\.id) == [code.id])
        #expect(selection.pendingCount == 1)
    }

    @Test @MainActor
    func migrationRetiresRedeemedAndRevokedStates() async throws {
        let fixture = try makeFixture(codeCount: 2)
        let codes = try fixture.container.mainContext.fetch(FetchDescriptor<OfferCode>(
            sortBy: [SortDescriptor(\.createdAt)]
        ))
        let redeemed = try #require(codes.first)
        let revoked = try #require(codes.last)
        let redeemedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let revokedAt = Date(timeIntervalSince1970: 1_710_000_000)
        redeemed.isRedeemed = true
        redeemed.redeemedDate = redeemedAt
        redeemed.redemptionCount = 1
        revoked.revokedAt = revokedAt
        try fixture.container.mainContext.save()

        try await CodeVaultMigrationService(modelContainer: fixture.container)
            .performAdditiveMigration()

        let context = ModelContext(fixture.container)
        let migrated = try context.fetch(FetchDescriptor<OfferCode>())
        let migratedRedeemed = try #require(migrated.first { $0.id == redeemed.id })
        let migratedRevoked = try #require(migrated.first { $0.id == revoked.id })
        #expect(migratedRedeemed.lifecycleStatus == .sent)
        #expect(migratedRedeemed.sentAt == redeemedAt)
        #expect(!migratedRedeemed.isRedeemed)
        #expect(migratedRedeemed.redemptionCount == 0)
        #expect(migratedRevoked.archivedAt == revokedAt)
        #expect(migratedRevoked.revokedAt == nil)
    }

    @Test @MainActor
    func undoReturnsOnlyNewlySentCodesToPending() async throws {
        let fixture = try makeFixture(codeCount: 3)
        let repository = CodeVaultRepository(modelContainer: fixture.container)
        let selection = try await repository.reserveCodes(
            categoryID: fixture.categoryID,
            quantity: 3
        )
        let firstID = try #require(selection.codes.first?.id)
        try await repository.markCodeSent(id: firstID)
        let pendingIDs = selection.codes.dropFirst().map(\.id)
        _ = try await repository.markSelectionSent(id: selection.id)

        try await repository.restoreCodesToPending(
            retrievalID: selection.id,
            codeIDs: pendingIDs
        )
        let restored = try #require(try await repository.loadSelection(id: selection.id))

        #expect(restored.codes.first { $0.id == firstID }?.status == .sent)
        #expect(restored.pendingCount == 2)
    }

    @MainActor
    private func makeFixture(
        codeCount: Int
    ) throws -> (container: ModelContainer, categoryID: UUID) {
        let container = try TestModelStore.makeInMemoryContainer()
        let app = AppRecord(name: "Example", appStoreId: "123")
        let category = CodeCategory(name: "Launch", productName: "Pro", app: app)
        let batch = CodeBatch(name: "Import", source: .csv)
        batch.app = app
        batch.category = category
        container.mainContext.insert(app)
        container.mainContext.insert(category)
        container.mainContext.insert(batch)
        for index in 0..<codeCount {
            let code = OfferCode(
                code: "CODE\(index)",
                redemptionURL: "https://example.com/CODE\(index)"
            )
            code.app = app
            code.batch = batch
            container.mainContext.insert(code)
        }
        try container.mainContext.save()
        return (container, category.id)
    }
}
