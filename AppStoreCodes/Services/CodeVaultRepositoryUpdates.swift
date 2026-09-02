import Foundation
import SwiftData

nonisolated struct CodeCategorySaveRequest: Sendable {
    let id: UUID?
    let appID: UUID
    let name: String
    let productName: String
    let productID: String?
    let offerReferenceName: String?
    let notes: String?
}

nonisolated enum CodeStatusAction: Sendable {
    case available
    case sent
}

extension CodeVaultRepository {
    func updateAppGreeting(id: UUID, greeting: String?) throws {
        guard let app = try modelContext.fetch(FetchDescriptor<AppRecord>(
            predicate: #Predicate { $0.id == id }
        )).first else {
            throw CodeVaultRepositoryError.appNotFound
        }
        app.qrGreeting = greeting?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        try modelContext.save()
    }

    func backfillAppMetadata(id: UUID, metadata: AppStoreMetadata) throws {
        guard let app = try modelContext.fetch(FetchDescriptor<AppRecord>(
            predicate: #Predicate { $0.id == id }
        )).first else {
            throw CodeVaultRepositoryError.appNotFound
        }
        if app.bundleId == nil { app.bundleId = metadata.bundleID }
        if app.iconURL == nil { app.iconURL = metadata.artworkURL }
        if app.appStoreURL == nil { app.appStoreURL = metadata.appStoreURL }
        if app.metadataLastUpdated == nil { app.metadataLastUpdated = Date() }
        try modelContext.save()
    }

    func saveCodeCategory(_ request: CodeCategorySaveRequest) throws {
        let appID = request.appID
        guard let app = try modelContext.fetch(FetchDescriptor<AppRecord>(
            predicate: #Predicate { $0.id == appID }
        )).first else {
            throw CodeVaultRepositoryError.appNotFound
        }
        let category: CodeCategory
        if let id = request.id {
            guard let existing = try modelContext.fetch(FetchDescriptor<CodeCategory>(
                predicate: #Predicate { $0.id == id }
            )).first else {
                throw CodeVaultRepositoryError.categoryNotFound
            }
            category = existing
        } else {
            category = CodeCategory(
                name: request.name,
                productName: request.productName,
                app: app
            )
            modelContext.insert(category)
        }
        category.name = request.name
        category.productName = request.productName
        category.productID = request.productID
        category.offerReferenceName = request.offerReferenceName
        category.notes = request.notes
        category.app = app
        category.archivedAt = nil
        try modelContext.save()
    }

    @discardableResult
    func updateCodeStatus(id: UUID, action: CodeStatusAction) throws -> CodeLifecycleStatus {
        guard let code = try modelContext.fetch(FetchDescriptor<OfferCode>(
            predicate: #Predicate { $0.id == id }
        )).first else {
            throw CodeVaultRepositoryError.codeNotFound
        }
        switch action {
        case .available: code.markAsAvailable()
        case .sent: code.markAsSent()
        }
        try modelContext.save()
        return code.lifecycleStatus
    }
}
