import Foundation
import SwiftData

extension DashboardRepository {
    func loadCodeCategories(
        appID: UUID,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> [CodeCategorySummary] {
        let categories = try modelContext.fetch(FetchDescriptor<CodeCategory>(
            predicate: #Predicate { category in
                category.app?.id == appID && category.archivedAt == nil
            }
        ))
        let codes = try modelContext.fetch(FetchDescriptor<OfferCode>(
            predicate: #Predicate { code in
                code.app?.id == appID && code.archivedAt == nil
            }
        ))
        let warningDate = calendar.date(byAdding: .day, value: 7, to: now) ?? now
        var counts: [UUID: (available: Int, total: Int, expiring: Int)] = [:]
        let activeCategoryIDs = Set(categories.map(\.id))

        for code in codes {
            guard let batch = code.batch,
                  !batch.isArchived,
                  let categoryID = batch.category?.id,
                  activeCategoryIDs.contains(categoryID) else { continue }
            var value = counts[categoryID] ?? (0, 0, 0)
            let isAvailable = code.isAvailable
            value.total += 1
            if isAvailable { value.available += 1 }
            if let expirationDate = code.expirationDate,
               isAvailable,
               expirationDate >= now,
               expirationDate <= warningDate {
                value.expiring += 1
            }
            counts[categoryID] = value
        }

        return categories.map { category in
            let value = counts[category.id] ?? (0, 0, 0)
            return CodeCategorySummary(
                id: category.id,
                name: category.name,
                productName: category.productName,
                productID: category.productID,
                offerReferenceName: category.offerReferenceName,
                notes: category.notes,
                availableCount: value.available,
                totalCount: value.total,
                expiringCount: value.expiring
            )
        }
        .sorted { left, right in
            if left.productName != right.productName {
                return left.productName.localizedStandardCompare(right.productName)
                    == .orderedAscending
            }
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
    }
}
