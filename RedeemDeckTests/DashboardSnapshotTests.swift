import Foundation
import SwiftData
import Testing
@testable import RedeemDeck

struct DashboardSnapshotTests {
    @Test @MainActor
    func categorySnapshotContainsEverythingNeededByNavigationAndEditing() async throws {
        let container = try TestModelStore.makeInMemoryContainer()
        let context = container.mainContext
        let app = AppRecord(name: "Example", appStoreId: "123")
        let category = CodeCategory(
            name: "Half Off",
            productName: "Pro Monthly",
            productID: "pro.monthly",
            offerReferenceName: "HALF_OFF",
            app: app
        )
        category.notes = "Launch offer"
        let batch = CodeBatch(name: "Import", source: .csv)
        batch.app = app
        batch.category = category
        let code = OfferCode(code: "CODE1", redemptionURL: "https://example.com/CODE1")
        code.app = app
        code.batch = batch
        context.insert(app)
        context.insert(category)
        context.insert(batch)
        context.insert(code)
        try context.save()

        let repository = DashboardRepository(modelContainer: container)
        let categories = try await repository.loadCodeCategories(appID: app.id)
        let snapshot = try #require(categories.first)
        let codes = try await repository.loadCategoryCodes(
            categoryID: category.id,
            searchText: "",
            filter: .all,
            limit: 200
        )
        let initialCode = try #require(codes.rows.first)

        #expect(snapshot.id == category.id)
        #expect(snapshot.name == "Half Off")
        #expect(snapshot.productName == "Pro Monthly")
        #expect(snapshot.productID == "pro.monthly")
        #expect(snapshot.offerReferenceName == "HALF_OFF")
        #expect(snapshot.notes == "Launch offer")
        #expect(snapshot.availableCount == 1)
        #expect(snapshot.totalCount == 1)
        #expect(initialCode.id == code.id)
        #expect(initialCode.code == "CODE1")
        #expect(codes.availableCount == 1)
    }

    @Test @MainActor
    func expiredReservationLeavesPendingRecoveryAndAppearsAsExpiredHistory() async throws {
        let container = try TestModelStore.makeInMemoryContainer()
        let app = AppRecord(name: "Example", appStoreId: "123")
        let category = CodeCategory(name: "Launch", productName: "Pro", app: app)
        let batch = CodeBatch(name: "Import", source: .csv)
        batch.app = app
        batch.category = category
        let code = OfferCode(
            code: "EXPIRED",
            redemptionURL: "https://example.com/EXPIRED",
            expirationDate: .distantPast
        )
        code.app = app
        code.batch = batch
        code.reservedAt = Date()
        code.retrievalID = UUID()
        container.mainContext.insert(app)
        container.mainContext.insert(category)
        container.mainContext.insert(batch)
        container.mainContext.insert(code)
        try container.mainContext.save()

        let repository = RedeemDeckRepository(modelContainer: container)
        let dashboard = DashboardRepository(modelContainer: container)
        let history = try await dashboard.loadRetrievalHistory(appID: app.id)

        #expect(try await repository.loadPendingSelections().isEmpty)
        #expect(history.first?.expiredCount == 1)
        #expect(history.first?.pendingCount == 0)
        #expect(history.first?.sentCount == 0)
    }
}
