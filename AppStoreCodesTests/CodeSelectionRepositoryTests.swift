import Foundation
import SwiftData
import Testing
@testable import CodeVault

struct CodeSelectionRepositoryTests {
    @Test @MainActor
    func nextCodeStaysInsideCategoryAndUsesEarliestExpiry() async throws {
        let container = try TestModelStore.makeInMemoryContainer()
        let context = container.mainContext
        let app = AppRecord(name: "Example", appStoreId: "123")
        let category = CodeCategory(name: "Half Off", productName: "Pro", app: app)
        let otherCategory = CodeCategory(name: "Free", productName: "Pro", app: app)
        let batch = CodeBatch(name: "Half Off Import", source: .csv)
        batch.app = app
        batch.category = category
        let otherBatch = CodeBatch(name: "Free Import", source: .csv)
        otherBatch.app = app
        otherBatch.category = otherCategory
        let later = makeCode("LATER1", days: 20, app: app, batch: batch)
        let earlier = makeCode("EARLIER1", days: 5, app: app, batch: batch)
        let outside = makeCode("OUTSIDE1", days: 1, app: app, batch: otherBatch)
        context.insert(app)
        context.insert(category)
        context.insert(otherCategory)
        context.insert(batch)
        context.insert(otherBatch)
        context.insert(later)
        context.insert(earlier)
        context.insert(outside)
        try context.save()
        let repository = CodeVaultRepository(modelContainer: container)

        let selection = try await repository.reserveCodes(
            categoryID: category.id,
            quantity: 2
        )
        #expect(selection.codes.map(\.code) == ["EARLIER1", "LATER1"])
        #expect(selection.pendingCount == 2)
        try await repository.markSelectionSent(id: selection.id)

        let verification = ModelContext(container)
        let savedCodes = try verification.fetch(FetchDescriptor<OfferCode>())
        #expect(savedCodes.first { $0.code == "EARLIER1" }?.lifecycleStatus == .sent)
        #expect(savedCodes.first { $0.code == "LATER1" }?.lifecycleStatus == .sent)
        #expect(savedCodes.first { $0.code == "OUTSIDE1" }?.lifecycleStatus == .available)
    }

    @Test @MainActor
    func releasingReservationMakesCodeAvailableAgain() async throws {
        let container = try TestModelStore.makeInMemoryContainer()
        let app = AppRecord(name: "Example", appStoreId: "123")
        let category = CodeCategory(name: "Launch", productName: "Pro", app: app)
        let batch = CodeBatch(name: "Import", source: .csv)
        batch.app = app
        batch.category = category
        let code = makeCode("CODE1", days: 10, app: app, batch: batch)
        container.mainContext.insert(app)
        container.mainContext.insert(category)
        container.mainContext.insert(batch)
        container.mainContext.insert(code)
        try container.mainContext.save()
        let repository = CodeVaultRepository(modelContainer: container)

        let selection = try await repository.reserveCodes(categoryID: category.id, quantity: 1)
        try await repository.releaseSelection(id: selection.id)

        let verification = ModelContext(container)
        #expect(try #require(verification.fetch(FetchDescriptor<OfferCode>()).first).isAvailable)
    }

    @Test @MainActor
    func categoryBrowserLimitsRowsAndReportsCompleteCounts() async throws {
        let container = try TestModelStore.makeInMemoryContainer()
        let app = AppRecord(name: "Large", appStoreId: "123")
        let category = CodeCategory(name: "Launch", productName: "Pro", app: app)
        let batch = CodeBatch(name: "Large Import", source: .csv)
        batch.app = app
        batch.category = category
        container.mainContext.insert(app)
        container.mainContext.insert(category)
        container.mainContext.insert(batch)
        for index in 0..<250 {
            let code = OfferCode(
                code: String(format: "CODE%04d", index),
                redemptionURL: "https://example.com/\(index)"
            )
            code.app = app
            code.batch = batch
            container.mainContext.insert(code)
        }
        try container.mainContext.save()
        let dashboard = DashboardRepository(modelContainer: container)

        let firstPage = try await dashboard.loadCategoryCodes(
            categoryID: category.id,
            searchText: "",
            filter: .all,
            limit: 200
        )
        let search = try await dashboard.loadCategoryCodes(
            categoryID: category.id,
            searchText: "CODE0249",
            filter: .all,
            limit: 200
        )

        #expect(firstPage.rows.count == 200)
        #expect(firstPage.matchingCount == 250)
        #expect(firstPage.availableCount == 250)
        #expect(search.rows.map(\.code) == ["CODE0249"])
    }

    @MainActor
    private func makeCode(
        _ value: String,
        days: Double,
        app: AppRecord,
        batch: CodeBatch
    ) -> OfferCode {
        let code = OfferCode(
            code: value,
            redemptionURL: "https://example.com/\(value)",
            expirationDate: Date().addingTimeInterval(86_400 * days)
        )
        code.app = app
        code.batch = batch
        return code
    }
}
