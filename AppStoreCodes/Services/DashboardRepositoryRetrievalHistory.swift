import Foundation
import SwiftData

extension DashboardRepository {
    func loadRetrievalHistory(appID: UUID, limit: Int = 20) throws -> [RetrievalHistorySummary] {
        let codes = try modelContext.fetch(FetchDescriptor<OfferCode>(
            predicate: #Predicate { code in
                code.app?.id == appID
                    && code.retrievalID != nil
                    && code.archivedAt == nil
            }
        ))
        let grouped = Dictionary(grouping: codes) { $0.retrievalID }
        return grouped.compactMap { retrievalID, group in
            guard let retrievalID, let first = group.first else { return nil }
            let statuses = group.map(\.lifecycleStatus)
            return RetrievalHistorySummary(
                id: retrievalID,
                categoryName: first.batch?.category?.name ?? String(localized: "Unassigned"),
                count: group.count,
                pendingCount: statuses.count { $0 == .pending },
                sentCount: statuses.count { $0 == .sent },
                expiredCount: statuses.count { $0 == .expired },
                createdAt: group.compactMap { $0.reservedAt ?? $0.sentAt }.min() ?? first.createdAt
            )
        }
        .sorted { $0.createdAt > $1.createdAt }
        .prefix(max(1, limit))
        .map { $0 }
    }
}
