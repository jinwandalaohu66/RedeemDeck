import Foundation
import SwiftData

extension BackupRepository {
    func restore(_ archive: RedeemDeckBackupArchive) throws -> BackupRestoreSummary {
        var summary: BackupRestoreSummary?
        try modelContext.transaction {
            let apps = try restoreApps(archive.apps)
            var categories = try restoreCategories(archive.categories ?? [], apps: apps)
            let campaigns = try restoreCampaigns(archive.campaigns, apps: apps)
            let recipients = try restoreRecipients(archive.recipients)
            let batches = try restoreBatches(
                archive.batches,
                apps: apps,
                categories: categories,
                campaigns: campaigns
            )
            try restoreMissingCategories(for: batches, into: &categories)
            let codes = try restoreCodes(archive.codes, apps: apps, batches: batches)
            try restoreDistributions(
                archive.distributions,
                codes: codes,
                recipients: recipients,
                campaigns: campaigns
            )
            try restoreActivities(archive.activities)
            try restoreTemplates(archive.templates)
            try modelContext.save()
            summary = BackupRestoreSummary(
                apps: archive.apps.count,
                categories: categories.count,
                batches: archive.batches.count,
                codes: archive.codes.count
            )
        }
        guard let summary else {
            throw BackupCodecError.invalidArchive
        }
        return summary
    }

    private func restoreCategories(
        _ records: [CodeCategoryBackupRecord],
        apps: [UUID: AppRecord]
    ) throws -> [UUID: CodeCategory] {
        let existing = try modelContext.fetch(FetchDescriptor<CodeCategory>())
        var byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        var restored: [UUID: CodeCategory] = [:]
        for item in records {
            let category = byID[item.id] ?? CodeCategory(
                name: item.name,
                productName: item.productName
            )
            if category.modelContext == nil {
                category.id = item.id
                modelContext.insert(category)
            }
            category.name = item.name
            category.productName = item.productName
            category.productID = item.productID
            category.offerReferenceName = item.offerReferenceName
            category.notes = item.notes
            category.createdAt = item.createdAt
            category.archivedAt = item.archivedAt
            category.app = item.appID.flatMap { apps[$0] }
            byID[category.id] = category
            restored[item.id] = category
        }
        return restored
    }

    /// Schema-one backups predate code categories. Reconstruct the canonical
    /// product/offer grouping without changing their batch or code history.
    private func restoreMissingCategories(
        for batches: [UUID: CodeBatch],
        into restored: inout [UUID: CodeCategory]
    ) throws {
        let existing = try modelContext.fetch(FetchDescriptor<CodeCategory>())
        var categoriesByKey: [RestoredCategoryKey: CodeCategory] = [:]

        for category in existing {
            guard let appID = category.app?.id else { continue }
            categoriesByKey[RestoredCategoryKey(
                appID: appID,
                product: category.productID ?? category.productName,
                offer: category.offerReferenceName ?? category.name
            )] = category
        }

        for batch in batches.values where batch.category == nil {
            guard let app = batch.app else { continue }
            let productName = batch.productID?.nilIfBlank ?? String(localized: "General")
            let categoryName = batch.offerReferenceName?.nilIfBlank ?? batch.name
            let key = RestoredCategoryKey(
                appID: app.id,
                product: batch.productID ?? productName,
                offer: batch.offerReferenceName ?? categoryName
            )
            let category: CodeCategory
            if let existing = categoriesByKey[key] {
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
                categoriesByKey[key] = category
            }
            batch.category = category
            restored[category.id] = category
        }
    }

    private func restoreApps(_ records: [AppBackupRecord]) throws -> [UUID: AppRecord] {
        let existing = try modelContext.fetch(FetchDescriptor<AppRecord>())
        var byID: [UUID: AppRecord] = [:]
        var byStoreID: [String: AppRecord] = [:]
        for app in existing {
            byID[app.id] = byID[app.id] ?? app
            byStoreID[app.appStoreId] = byStoreID[app.appStoreId] ?? app
        }
        var restored: [UUID: AppRecord] = [:]
        for item in records {
            let app = byID[item.id] ?? byStoreID[item.appStoreID]
                ?? AppRecord(name: item.name, appStoreId: item.appStoreID)
            if app.modelContext == nil {
                app.id = item.id
                modelContext.insert(app)
            }
            apply(item, to: app)
            byID[app.id] = app
            byStoreID[app.appStoreId] = app
            restored[item.id] = app
        }
        return restored
    }

    private func restoreCampaigns(
        _ records: [CampaignBackupRecord],
        apps: [UUID: AppRecord]
    ) throws -> [UUID: Campaign] {
        let existing = try modelContext.fetch(FetchDescriptor<Campaign>())
        var byID: [UUID: Campaign] = [:]
        for campaign in existing { byID[campaign.id] = byID[campaign.id] ?? campaign }
        var restored: [UUID: Campaign] = [:]
        for item in records {
            let campaign = byID[item.id] ?? Campaign(name: item.name)
            if campaign.modelContext == nil {
                campaign.id = item.id
                modelContext.insert(campaign)
            }
            campaign.name = item.name
            campaign.goal = item.goal
            campaign.notes = item.notes
            campaign.statusRawValue = item.status
            campaign.startDate = item.startDate
            campaign.endDate = item.endDate
            campaign.createdAt = item.createdAt
            campaign.updatedAt = item.updatedAt
            campaign.app = item.appID.flatMap { apps[$0] }
            byID[campaign.id] = campaign
            restored[item.id] = campaign
        }
        return restored
    }

    private func restoreRecipients(
        _ records: [RecipientBackupRecord]
    ) throws -> [UUID: Recipient] {
        let existing = try modelContext.fetch(FetchDescriptor<Recipient>())
        var byID: [UUID: Recipient] = [:]
        for recipient in existing { byID[recipient.id] = byID[recipient.id] ?? recipient }
        var restored: [UUID: Recipient] = [:]
        for item in records {
            let recipient = byID[item.id] ?? Recipient(name: item.name)
            if recipient.modelContext == nil {
                recipient.id = item.id
                modelContext.insert(recipient)
            }
            recipient.name = item.name
            recipient.organization = item.organization
            recipient.contact = item.contact
            recipient.preferredChannelRawValue = item.preferredChannel
            recipient.localeIdentifier = item.localeIdentifier
            recipient.tagsText = item.tagsText
            recipient.notes = item.notes
            recipient.createdAt = item.createdAt
            recipient.updatedAt = item.updatedAt
            recipient.archivedAt = item.archivedAt
            byID[recipient.id] = recipient
            restored[item.id] = recipient
        }
        return restored
    }

    private func restoreBatches(
        _ records: [BatchBackupRecord],
        apps: [UUID: AppRecord],
        categories: [UUID: CodeCategory],
        campaigns: [UUID: Campaign]
    ) throws -> [UUID: CodeBatch] {
        let existing = try modelContext.fetch(FetchDescriptor<CodeBatch>())
        var byID: [UUID: CodeBatch] = [:]
        for batch in existing { byID[batch.id] = byID[batch.id] ?? batch }
        var restored: [UUID: CodeBatch] = [:]
        for item in records {
            let source = ImportSource(rawValue: item.source) ?? .csv
            let batch = byID[item.id] ?? CodeBatch(name: item.name, source: source)
            if batch.modelContext == nil {
                batch.id = item.id
                modelContext.insert(batch)
            }
            apply(item, to: batch)
            batch.app = item.appID.flatMap { apps[$0] }
            batch.category = item.categoryID.flatMap { categories[$0] }
            batch.campaign = item.campaignID.flatMap { campaigns[$0] }
            byID[batch.id] = batch
            restored[item.id] = batch
        }
        return restored
    }

    private func restoreCodes(
        _ records: [CodeBackupRecord],
        apps: [UUID: AppRecord],
        batches: [UUID: CodeBatch]
    ) throws -> [UUID: OfferCode] {
        let existing = try modelContext.fetch(FetchDescriptor<OfferCode>())
        var byID: [UUID: OfferCode] = [:]
        var byNaturalKey: [CodeRestoreKey: OfferCode] = [:]
        for code in existing {
            byID[code.id] = byID[code.id] ?? code
            let key = CodeRestoreKey(appID: code.app?.id, code: code.code)
            byNaturalKey[key] = byNaturalKey[key] ?? code
        }
        var restored: [UUID: OfferCode] = [:]
        for item in records {
            let resolvedAppID = item.appID.flatMap { apps[$0]?.id }
            let key = CodeRestoreKey(appID: resolvedAppID, code: item.code)
            let code = byID[item.id] ?? byNaturalKey[key]
                ?? OfferCode(code: item.code, redemptionURL: item.redemptionURL)
            if code.modelContext == nil {
                code.id = item.id
                modelContext.insert(code)
            }
            apply(item, to: code)
            code.app = item.appID.flatMap { apps[$0] }
            code.batch = item.batchID.flatMap { batches[$0] }
            byID[code.id] = code
            byNaturalKey[key] = code
            restored[item.id] = code
        }
        return restored
    }
}

private nonisolated struct CodeRestoreKey: Hashable {
    let appID: UUID?
    let code: String
}

private nonisolated struct RestoredCategoryKey: Hashable {
    let appID: UUID
    let product: String
    let offer: String

    init(appID: UUID, product: String, offer: String) {
        self.appID = appID
        self.product = product.trimmed.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        self.offer = offer.trimmed.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
    }
}
