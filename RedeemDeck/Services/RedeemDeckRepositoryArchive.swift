import Foundation
import SwiftData

nonisolated enum ArchiveTarget: Sendable {
    case app(UUID)
    case category(UUID)
    case batch(UUID)

    var id: UUID {
        switch self {
        case .app(let id), .category(let id), .batch(let id): id
        }
    }
}

extension RedeemDeckRepository {
    func setArchived(_ target: ArchiveTarget, archived: Bool) throws {
        let archivedAt = archived ? Date() : nil

        switch target {
        case .app(let id):
            guard let app = try modelContext.fetch(FetchDescriptor<AppRecord>(
                predicate: #Predicate { $0.id == id }
            )).first else { throw RedeemDeckRepositoryError.appNotFound }
            app.archivedAt = archivedAt
        case .category(let id):
            guard let category = try modelContext.fetch(FetchDescriptor<CodeCategory>(
                predicate: #Predicate { $0.id == id }
            )).first else { throw RedeemDeckRepositoryError.categoryNotFound }
            category.archivedAt = archivedAt
        case .batch(let id):
            guard let batch = try modelContext.fetch(FetchDescriptor<CodeBatch>(
                predicate: #Predicate { $0.id == id }
            )).first else { throw RedeemDeckRepositoryError.batchNotFound }
            batch.archivedAt = archivedAt
        }
        try modelContext.save()
    }
}
