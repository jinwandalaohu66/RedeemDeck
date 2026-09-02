import Foundation
import SwiftData

extension BackupRepository {
    func restoreDistributions(
        _ records: [DistributionBackupRecord],
        codes: [UUID: OfferCode],
        recipients: [UUID: Recipient],
        campaigns: [UUID: Campaign]
    ) throws {
        let existing = try modelContext.fetch(FetchDescriptor<DistributionRecord>())
        var byID: [UUID: DistributionRecord] = [:]
        for value in existing { byID[value.id] = byID[value.id] ?? value }
        for item in records {
            guard let codeID = item.codeID, let code = codes[codeID] else { continue }
            let distribution = byID[item.id] ?? DistributionRecord(code: code)
            if distribution.modelContext == nil {
                distribution.id = item.id
                modelContext.insert(distribution)
            }
            distribution.stateRawValue = item.state
            distribution.channelRawValue = item.channel
            distribution.preparedAt = item.preparedAt
            distribution.sentAt = item.sentAt
            distribution.completedAt = item.completedAt
            distribution.followUpDate = item.followUpDate
            distribution.message = item.message
            distribution.notes = item.notes
            distribution.recipientNameSnapshot = item.recipientNameSnapshot
            distribution.campaignNameSnapshot = item.campaignNameSnapshot
            distribution.code = code
            distribution.recipient = item.recipientID.flatMap { recipients[$0] }
            distribution.campaign = item.campaignID.flatMap { campaigns[$0] }
            byID[distribution.id] = distribution
        }
    }

    func restoreActivities(_ records: [ActivityBackupRecord]) throws {
        let existing = try modelContext.fetch(FetchDescriptor<ActivityEvent>())
        var byID: [UUID: ActivityEvent] = [:]
        for value in existing { byID[value.id] = byID[value.id] ?? value }
        for item in records {
            let activity = byID[item.id]
                ?? ActivityEvent(
                    kindRawValue: item.kind,
                    title: item.title,
                    timestamp: item.timestamp
                )
            if activity.modelContext == nil {
                activity.id = item.id
                modelContext.insert(activity)
            }
            activity.kindRawValue = item.kind
            activity.timestamp = item.timestamp
            activity.title = item.title
            activity.detail = item.detail
            activity.appID = item.appID
            activity.campaignID = item.campaignID
            activity.codeID = item.codeID
            activity.recipientID = item.recipientID
            byID[activity.id] = activity
        }
    }

    func restoreTemplates(_ records: [TemplateBackupRecord]) throws {
        let existing = try modelContext.fetch(FetchDescriptor<MessageTemplate>())
        var byID: [UUID: MessageTemplate] = [:]
        for value in existing { byID[value.id] = byID[value.id] ?? value }
        for item in records {
            let template = byID[item.id]
                ?? MessageTemplate(name: item.name, body: item.body)
            if template.modelContext == nil {
                template.id = item.id
                modelContext.insert(template)
            }
            template.name = item.name
            template.body = item.body
            template.localeIdentifier = item.localeIdentifier
            template.channelRawValue = item.channel
            template.isDefault = item.isDefault
            template.createdAt = item.createdAt
            template.updatedAt = item.updatedAt
            byID[template.id] = template
        }
    }

    func apply(_ item: AppBackupRecord, to app: AppRecord) {
        app.name = item.name
        app.appStoreId = item.appStoreID
        app.bundleId = item.bundleID
        app.iconURL = item.iconURL
        app.appStoreURL = item.appStoreURL
        app.developerName = item.developerName
        app.appDescription = item.appDescription
        app.version = item.version
        app.releaseDate = item.releaseDate
        app.primaryGenre = item.primaryGenre
        app.price = item.price
        app.currency = item.currency
        app.testFlightURL = item.testFlightURL
        app.testFlightNotes = item.testFlightNotes
        app.notes = item.notes
        app.qrGreeting = item.qrGreeting
        app.metadataLastUpdated = item.metadataLastUpdated
        app.createdAt = item.createdAt
        app.archivedAt = item.archivedAt
    }

    func apply(_ item: BatchBackupRecord, to batch: CodeBatch) {
        batch.name = item.name
        batch.importDate = item.importDate
        batch.sourceRawValue = item.source
        batch.notes = item.notes
        batch.expirationDate = item.expirationDate
        batch.codeKindRawValue = item.codeKind
        batch.environmentRawValue = item.environment
        batch.platformRawValue = item.platform
        batch.appVersion = item.appVersion
        batch.productID = item.productID
        batch.offerReferenceName = item.offerReferenceName
        batch.redemptionLimit = item.redemptionLimit
        batch.archivedAt = item.archivedAt
    }

    func apply(_ item: CodeBackupRecord, to code: OfferCode) {
        code.code = item.code
        code.redemptionURL = item.redemptionURL
        code.isRedeemed = item.isRedeemed
        code.redeemedDate = item.redeemedDate
        code.sentAt = item.sentAt
        code.assignedTo = item.assignedTo
        code.notes = item.notes
        code.createdAt = item.createdAt
        code.expirationDate = item.expirationDate
        code.reservedAt = item.reservedAt
        code.retrievalID = item.retrievalID
        code.revokedAt = item.revokedAt
        code.redemptionCount = item.redemptionCount
        code.archivedAt = item.archivedAt
        code.firstSeenAt = item.firstSeenAt
        code.lastSeenAt = item.lastSeenAt
        code.trackingVisitCount = item.trackingVisitCount
        code.trackingLinkID = item.trackingLinkID
        code.trackedURL = item.trackedURL
        code.trackingAPIBaseURL = item.trackingAPIBaseURL
        code.trackingCreatedAt = item.trackingCreatedAt
        code.trackingLastSyncedAt = item.trackingLastSyncedAt
        code.normalizeRetiredLifecycle()
    }
}
