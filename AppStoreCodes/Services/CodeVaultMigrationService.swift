import Foundation
import SwiftData

@ModelActor
actor CodeVaultMigrationService {
    func performAdditiveMigration() throws {
        try normalizeRetiredCodeStates()
        try backfillBatchKinds()
        try backfillCodeCategories()
        try backfillRetrievalIDs()
        try modelContext.save()
    }

    private func normalizeRetiredCodeStates() throws {
        let codes = try modelContext.fetch(FetchDescriptor<OfferCode>(
            predicate: #Predicate { code in
                code.isRedeemed
                    || code.redeemedDate != nil
                    || code.redemptionCount > 0
                    || code.revokedAt != nil
            }
        ))
        for code in codes {
            code.normalizeRetiredLifecycle()
        }
    }

    /// A previous app version could leave one transient reservation behind if
    /// it was terminated while the quick-code sheet was open. Give each such
    /// reservation a durable retrieval identity so it appears in recovery UI.
    private func backfillRetrievalIDs() throws {
        let codes = try modelContext.fetch(FetchDescriptor<OfferCode>(
            predicate: #Predicate { code in
                code.reservedAt != nil && code.retrievalID == nil
            }
        ))
        for code in codes {
            code.retrievalID = UUID()
        }
    }

    private func backfillBatchKinds() throws {
        let batches = try modelContext.fetch(FetchDescriptor<CodeBatch>())
        for batch in batches where batch.codeKind == .unknown {
            let sampleURL = batch.codes?.first?.redemptionURL ?? ""
            batch.codeKind = sampleURL.localizedCaseInsensitiveContains("offercodes")
                ? .oneTimeOffer
                : .appPromo
        }
    }

    private func backfillCodeCategories() throws {
        let categories = try modelContext.fetch(FetchDescriptor<CodeCategory>())
        var categoryByKey: [CategoryMigrationKey: CodeCategory] = [:]
        for category in categories {
            guard let appID = category.app?.id else { continue }
            categoryByKey[CategoryMigrationKey(
                appID: appID,
                product: normalized(category.productID ?? category.productName),
                offer: normalized(category.offerReferenceName ?? category.name)
            )] = category
        }

        let batches = try modelContext.fetch(FetchDescriptor<CodeBatch>())
        for batch in batches where batch.category == nil {
            guard let app = batch.app else { continue }
            let productName = batch.productID?.nilIfBlank ?? String(localized: "General")
            let categoryName = batch.offerReferenceName?.nilIfBlank ?? batch.name
            let key = CategoryMigrationKey(
                appID: app.id,
                product: normalized(batch.productID ?? productName),
                offer: normalized(batch.offerReferenceName ?? categoryName)
            )
            let category: CodeCategory
            if let existing = categoryByKey[key] {
                category = existing
            } else {
                category = CodeCategory(
                    name: categoryName,
                    productName: productName,
                    productID: batch.productID,
                    offerReferenceName: batch.offerReferenceName,
                    app: app
                )
                modelContext.insert(category)
                categoryByKey[key] = category
            }
            batch.category = category
        }
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

private nonisolated struct CategoryMigrationKey: Hashable {
    let appID: UUID
    let product: String
    let offer: String
}
