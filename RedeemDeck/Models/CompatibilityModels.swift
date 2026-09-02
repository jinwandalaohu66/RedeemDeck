import Foundation
import SwiftData

// Retained so existing databases and backups remain readable.

@Model
final class Campaign {
    var id: UUID = UUID()
    var name: String = ""
    var goal: String?
    var notes: String?
    var statusRawValue: String = "planned"
    var startDate: Date?
    var endDate: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var app: AppRecord?

    @Relationship(deleteRule: .nullify, inverse: \CodeBatch.campaign)
    var batches: [CodeBatch]?

    @Relationship(deleteRule: .nullify, inverse: \DistributionRecord.campaign)
    var distributions: [DistributionRecord]?

    init(name: String, app: AppRecord? = nil) {
        self.id = UUID()
        self.name = name
        self.app = app
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

@Model
final class Recipient {
    var id: UUID = UUID()
    var name: String = ""
    var organization: String?
    var contact: String?
    var preferredChannelRawValue: String = "systemShare"
    var localeIdentifier: String?
    var tagsText: String = ""
    var notes: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var archivedAt: Date?

    @Relationship(deleteRule: .nullify, inverse: \DistributionRecord.recipient)
    var distributions: [DistributionRecord]?

    init(
        name: String,
        organization: String? = nil,
        contact: String? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.organization = organization
        self.contact = contact
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

@Model
final class MessageTemplate {
    var id: UUID = UUID()
    var name: String = ""
    var body: String = ""
    var localeIdentifier: String = "en"
    var channelRawValue: String = "systemShare"
    var isDefault: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        name: String,
        body: String,
        localeIdentifier: String = "en",
        isDefault: Bool = false
    ) {
        self.id = UUID()
        self.name = name
        self.body = body
        self.localeIdentifier = localeIdentifier
        self.isDefault = isDefault
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

@Model
final class DistributionRecord {
    var id: UUID = UUID()
    var stateRawValue: String = "prepared"
    var channelRawValue: String = "systemShare"
    var preparedAt: Date = Date()
    var sentAt: Date?
    var completedAt: Date?
    var followUpDate: Date?
    var message: String?
    var notes: String?
    var recipientNameSnapshot: String?
    var campaignNameSnapshot: String?

    var code: OfferCode?
    var recipient: Recipient?
    var campaign: Campaign?

    init(code: OfferCode) {
        self.id = UUID()
        self.code = code
        self.preparedAt = Date()
    }
}

@Model
final class ActivityEvent {
    var id: UUID = UUID()
    var kindRawValue: String = "statusChanged"
    var timestamp: Date = Date()
    var title: String = ""
    var detail: String?
    var appID: UUID?
    var campaignID: UUID?
    var codeID: UUID?
    var recipientID: UUID?

    init(
        kindRawValue: String,
        title: String,
        detail: String? = nil,
        appID: UUID? = nil,
        campaignID: UUID? = nil,
        codeID: UUID? = nil,
        recipientID: UUID? = nil,
        timestamp: Date = Date()
    ) {
        self.id = UUID()
        self.kindRawValue = kindRawValue
        self.timestamp = timestamp
        self.title = title
        self.detail = detail
        self.appID = appID
        self.campaignID = campaignID
        self.codeID = codeID
        self.recipientID = recipientID
    }
}
