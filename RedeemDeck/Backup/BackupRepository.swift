import Foundation
import SwiftData

nonisolated struct BackupRestoreSummary: Sendable {
    let apps: Int
    let categories: Int
    let batches: Int
    let codes: Int
}

@ModelActor
actor BackupRepository {
    func makeArchive() throws -> RedeemDeckBackupArchive {
        let apps = try modelContext.fetch(FetchDescriptor<AppRecord>()).map {
            AppBackupRecord(
                id: $0.id, name: $0.name, appStoreID: $0.appStoreId,
                bundleID: $0.bundleId, iconURL: $0.iconURL, appStoreURL: $0.appStoreURL,
                developerName: $0.developerName, appDescription: $0.appDescription,
                version: $0.version, releaseDate: $0.releaseDate,
                primaryGenre: $0.primaryGenre, price: $0.price, currency: $0.currency,
                testFlightURL: $0.testFlightURL, testFlightNotes: $0.testFlightNotes,
                notes: $0.notes, qrGreeting: $0.qrGreeting,
                metadataLastUpdated: $0.metadataLastUpdated,
                createdAt: $0.createdAt, archivedAt: $0.archivedAt
            )
        }
        let batches = try modelContext.fetch(FetchDescriptor<CodeBatch>()).map {
            BatchBackupRecord(
                id: $0.id, name: $0.name, importDate: $0.importDate,
                source: $0.sourceRawValue, notes: $0.notes,
                expirationDate: $0.expirationDate, codeKind: $0.codeKindRawValue,
                environment: $0.environmentRawValue, platform: $0.platformRawValue,
                appVersion: $0.appVersion, productID: $0.productID,
                offerReferenceName: $0.offerReferenceName,
                redemptionLimit: $0.redemptionLimit, archivedAt: $0.archivedAt,
                appID: $0.app?.id, categoryID: $0.category?.id,
                campaignID: $0.campaign?.id
            )
        }
        let codes = try modelContext.fetch(FetchDescriptor<OfferCode>()).map {
            CodeBackupRecord(
                id: $0.id, code: $0.code, redemptionURL: $0.redemptionURL,
                isRedeemed: $0.isRedeemed, redeemedDate: $0.redeemedDate,
                sentAt: $0.sentAt, assignedTo: $0.assignedTo, notes: $0.notes,
                createdAt: $0.createdAt, expirationDate: $0.expirationDate,
                reservedAt: $0.reservedAt, retrievalID: $0.retrievalID,
                revokedAt: $0.revokedAt,
                redemptionCount: $0.redemptionCount, archivedAt: $0.archivedAt,
                firstSeenAt: $0.firstSeenAt, lastSeenAt: $0.lastSeenAt,
                trackingVisitCount: $0.trackingVisitCount,
                trackingLinkID: $0.trackingLinkID, trackedURL: $0.trackedURL,
                trackingAPIBaseURL: $0.trackingAPIBaseURL,
                trackingCreatedAt: $0.trackingCreatedAt,
                trackingLastSyncedAt: $0.trackingLastSyncedAt,
                appID: $0.app?.id, batchID: $0.batch?.id
            )
        }
        return RedeemDeckBackupArchive(
            schemaVersion: RedeemDeckBackupArchive.currentVersion,
            createdAt: Date(),
            apps: apps,
            categories: try backupCategories(),
            batches: batches,
            codes: codes,
            campaigns: try backupCampaigns(),
            recipients: try backupRecipients(),
            distributions: try backupDistributions(),
            activities: try backupActivities(),
            templates: try backupTemplates()
        )
    }

    private func backupCategories() throws -> [CodeCategoryBackupRecord] {
        try modelContext.fetch(FetchDescriptor<CodeCategory>()).map {
            CodeCategoryBackupRecord(
                id: $0.id,
                name: $0.name,
                productName: $0.productName,
                productID: $0.productID,
                offerReferenceName: $0.offerReferenceName,
                notes: $0.notes,
                createdAt: $0.createdAt,
                archivedAt: $0.archivedAt,
                appID: $0.app?.id
            )
        }
    }

    private func backupCampaigns() throws -> [CampaignBackupRecord] {
        try modelContext.fetch(FetchDescriptor<Campaign>()).map {
            CampaignBackupRecord(
                id: $0.id, name: $0.name, goal: $0.goal, notes: $0.notes,
                status: $0.statusRawValue, startDate: $0.startDate, endDate: $0.endDate,
                createdAt: $0.createdAt, updatedAt: $0.updatedAt, appID: $0.app?.id
            )
        }
    }

    private func backupRecipients() throws -> [RecipientBackupRecord] {
        try modelContext.fetch(FetchDescriptor<Recipient>()).map {
            RecipientBackupRecord(
                id: $0.id, name: $0.name, organization: $0.organization,
                contact: $0.contact, preferredChannel: $0.preferredChannelRawValue,
                localeIdentifier: $0.localeIdentifier, tagsText: $0.tagsText,
                notes: $0.notes, createdAt: $0.createdAt, updatedAt: $0.updatedAt,
                archivedAt: $0.archivedAt
            )
        }
    }

    private func backupDistributions() throws -> [DistributionBackupRecord] {
        try modelContext.fetch(FetchDescriptor<DistributionRecord>()).map {
            DistributionBackupRecord(
                id: $0.id, state: $0.stateRawValue, channel: $0.channelRawValue,
                preparedAt: $0.preparedAt, sentAt: $0.sentAt,
                completedAt: $0.completedAt, followUpDate: $0.followUpDate,
                message: $0.message, notes: $0.notes,
                recipientNameSnapshot: $0.recipientNameSnapshot,
                campaignNameSnapshot: $0.campaignNameSnapshot,
                codeID: $0.code?.id, recipientID: $0.recipient?.id,
                campaignID: $0.campaign?.id
            )
        }
    }

    private func backupActivities() throws -> [ActivityBackupRecord] {
        try modelContext.fetch(FetchDescriptor<ActivityEvent>()).map {
            ActivityBackupRecord(
                id: $0.id, kind: $0.kindRawValue, timestamp: $0.timestamp,
                title: $0.title, detail: $0.detail, appID: $0.appID,
                campaignID: $0.campaignID, codeID: $0.codeID,
                recipientID: $0.recipientID
            )
        }
    }

    private func backupTemplates() throws -> [TemplateBackupRecord] {
        try modelContext.fetch(FetchDescriptor<MessageTemplate>()).map {
            TemplateBackupRecord(
                id: $0.id, name: $0.name, body: $0.body,
                localeIdentifier: $0.localeIdentifier, channel: $0.channelRawValue,
                isDefault: $0.isDefault, createdAt: $0.createdAt, updatedAt: $0.updatedAt
            )
        }
    }
}
