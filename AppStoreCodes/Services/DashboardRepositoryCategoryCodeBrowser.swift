import Foundation
import SwiftData

extension DashboardRepository {
    func loadCategoryCodes(
        categoryID: UUID,
        searchText: String,
        filter: CodeBrowserFilter,
        limit: Int
    ) throws -> CodeCategoryCodeSnapshot {
        guard let category = try modelContext.fetch(FetchDescriptor<CodeCategory>(
            predicate: #Predicate { $0.id == categoryID }
        )).first, !category.isArchived else {
            return .empty
        }
        let codes = (category.batches ?? [])
            .filter { !$0.isArchived }
            .flatMap { $0.codes ?? [] }
            .filter { !$0.isArchived }
        return makeCategoryCodeSnapshot(
            codes: codes,
            searchText: searchText,
            filter: filter,
            limit: limit
        )
    }

    func makeCategoryCodeSnapshot(
        codes: [OfferCode],
        searchText: String,
        filter: CodeBrowserFilter,
        limit: Int
    ) -> CodeCategoryCodeSnapshot {
        let normalizedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var availableCount = 0
        var matching: [OfferCode] = []
        matching.reserveCapacity(min(codes.count, max(limit, 200)))

        for code in codes {
            let status = code.lifecycleStatus
            if code.isAvailable { availableCount += 1 }
            guard filter.includes(status) else { continue }
            guard normalizedSearch.isEmpty
                    || code.code.localizedStandardContains(normalizedSearch) else { continue }
            matching.append(code)
        }

        matching.sort { left, right in
            let leftExpiration = left.expirationDate ?? .distantFuture
            let rightExpiration = right.expirationDate ?? .distantFuture
            if leftExpiration != rightExpiration { return leftExpiration < rightExpiration }
            return left.createdAt < right.createdAt
        }

        let rows = matching.prefix(max(1, limit)).map {
            CodeRowSummary(
                id: $0.id,
                code: $0.code,
                redemptionURL: $0.redemptionURL,
                status: $0.lifecycleStatus,
                expirationDate: $0.expirationDate,
                notes: $0.notes
            )
        }
        return CodeCategoryCodeSnapshot(
            rows: Array(rows),
            matchingCount: matching.count,
            availableCount: availableCount,
            totalCount: codes.count
        )
    }
}
