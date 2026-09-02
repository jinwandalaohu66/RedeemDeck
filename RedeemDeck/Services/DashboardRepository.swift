import Foundation
import SwiftData

nonisolated struct AppInventorySummary: Identifiable, Sendable {
    let id: UUID
    let name: String
    let availableCount: Int
    let totalCount: Int
    let categoryCount: Int
    let expiringCount: Int
}

@ModelActor
actor DashboardRepository {
    func loadLibraryInventory(
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> [AppInventorySummary] {
        let apps = try modelContext.fetch(FetchDescriptor<AppRecord>(
            predicate: #Predicate { $0.archivedAt == nil }
        ))
        let codes = try modelContext.fetch(FetchDescriptor<OfferCode>(
            predicate: #Predicate { $0.archivedAt == nil }
        ))
        let categories = try modelContext.fetch(FetchDescriptor<CodeCategory>(
            predicate: #Predicate { $0.archivedAt == nil }
        ))

        let warningDate = calendar.date(byAdding: .day, value: 7, to: now) ?? now
        var inventoryByApp: [UUID: (available: Int, total: Int, expiring: Int)] = [:]
        var categoryCountByApp: [UUID: Int] = [:]

        for category in categories {
            guard let appID = category.app?.id else { continue }
            categoryCountByApp[appID, default: 0] += 1
        }

        for code in codes {
            if code.batch?.category?.isArchived == true { continue }
            guard let appID = code.app?.id else { continue }
            var counts = inventoryByApp[appID] ?? (0, 0, 0)
            let isAvailable = code.isAvailable
            counts.total += 1
            if isAvailable {
                counts.available += 1
            }
            if let expirationDate = code.expirationDate,
               isAvailable,
               expirationDate >= now,
               expirationDate <= warningDate {
                counts.expiring += 1
            }
            inventoryByApp[appID] = counts
        }

        return apps.map { app in
            let counts = inventoryByApp[app.id] ?? (0, 0, 0)
            return AppInventorySummary(
                id: app.id,
                name: app.name,
                availableCount: counts.available,
                totalCount: counts.total,
                categoryCount: categoryCountByApp[app.id] ?? 0,
                expiringCount: counts.expiring
            )
        }
        .sorted { left, right in
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
    }
}
