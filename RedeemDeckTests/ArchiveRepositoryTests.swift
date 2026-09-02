import Foundation
import SwiftData
import Testing
@testable import RedeemDeck

struct ArchiveRepositoryTests {
    @Test @MainActor
    func archiveAndRestorePersistThroughRepositoryActor() async throws {
        let container = try TestModelStore.makeInMemoryContainer()
        let app = AppRecord(name: "Example", appStoreId: "123")
        let category = CodeCategory(name: "Launch", productName: "Pro", app: app)
        container.mainContext.insert(app)
        container.mainContext.insert(category)
        try container.mainContext.save()
        let repository = RedeemDeckRepository(modelContainer: container)

        try await repository.setArchived(.app(app.id), archived: true)
        try await repository.setArchived(.category(category.id), archived: true)
        try await repository.setArchived(.app(app.id), archived: false)

        let context = ModelContext(container)
        let savedApp = try #require(context.fetch(FetchDescriptor<AppRecord>()).first)
        let savedCategory = try #require(context.fetch(FetchDescriptor<CodeCategory>()).first)
        #expect(savedApp.archivedAt == nil)
        #expect(savedCategory.archivedAt != nil)
        #expect(try context.fetch(FetchDescriptor<ActivityEvent>()).isEmpty)
    }

    @Test @MainActor
    func archivedParentsDoNotScheduleExpirationReminders() async throws {
        let container = try TestModelStore.makeInMemoryContainer()
        let app = AppRecord(name: "Example", appStoreId: "123")
        let category = CodeCategory(name: "Launch", productName: "Pro", app: app)
        let batch = CodeBatch(
            name: "Launch Codes",
            source: .csv,
            expirationDate: Date().addingTimeInterval(86_400 * 14)
        )
        batch.app = app
        batch.category = category
        let code = OfferCode(code: "ACTIVE", redemptionURL: "https://example.com")
        code.app = app
        code.batch = batch
        container.mainContext.insert(app)
        container.mainContext.insert(category)
        container.mainContext.insert(batch)
        container.mainContext.insert(code)
        try container.mainContext.save()

        let dashboard = DashboardRepository(modelContainer: container)
        #expect(try await dashboard.loadExpirationNotificationSnapshots().count == 1)

        let repository = RedeemDeckRepository(modelContainer: container)
        try await repository.setArchived(.category(category.id), archived: true)
        #expect(try await dashboard.loadExpirationNotificationSnapshots().isEmpty)
    }
}
