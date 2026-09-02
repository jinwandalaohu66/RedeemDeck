import Foundation
import SwiftData

extension DashboardRepository {
    func loadExpirationNotificationSnapshots() throws -> [ExpirationNotificationSnapshot] {
        let batches = try modelContext.fetch(FetchDescriptor<CodeBatch>(
            predicate: #Predicate { batch in
                batch.archivedAt == nil && batch.expirationDate != nil
            }
        ))
        let codes = try modelContext.fetch(FetchDescriptor<OfferCode>(
            predicate: #Predicate { $0.archivedAt == nil }
        )).filter(\.isAvailable)
        let availableBatchIDs = Set(codes.compactMap { $0.batch?.id })

        return batches.compactMap { batch in
            guard availableBatchIDs.contains(batch.id),
                  batch.category?.archivedAt == nil,
                  batch.app?.archivedAt == nil,
                  let expirationDate = batch.expirationDate else { return nil }
            return ExpirationNotificationSnapshot(
                batchID: batch.id,
                batchName: batch.name,
                appName: batch.app?.name,
                expirationDate: expirationDate
            )
        }
    }
}
