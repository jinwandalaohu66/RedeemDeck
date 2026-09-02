import Foundation

nonisolated struct CampaignBackupRecord: Codable, Sendable {
    let id: UUID
    let name: String
    let goal: String?
    let notes: String?
    let status: String
    let startDate: Date?
    let endDate: Date?
    let createdAt: Date
    let updatedAt: Date
    let appID: UUID?
}

nonisolated struct RecipientBackupRecord: Codable, Sendable {
    let id: UUID
    let name: String
    let organization: String?
    let contact: String?
    let preferredChannel: String
    let localeIdentifier: String?
    let tagsText: String
    let notes: String?
    let createdAt: Date
    let updatedAt: Date
    let archivedAt: Date?
}

nonisolated struct DistributionBackupRecord: Codable, Sendable {
    let id: UUID
    let state: String
    let channel: String
    let preparedAt: Date
    let sentAt: Date?
    let completedAt: Date?
    let followUpDate: Date?
    let message: String?
    let notes: String?
    let recipientNameSnapshot: String?
    let campaignNameSnapshot: String?
    let codeID: UUID?
    let recipientID: UUID?
    let campaignID: UUID?
}

nonisolated struct ActivityBackupRecord: Codable, Sendable {
    let id: UUID
    let kind: String
    let timestamp: Date
    let title: String
    let detail: String?
    let appID: UUID?
    let campaignID: UUID?
    let codeID: UUID?
    let recipientID: UUID?
}

nonisolated struct TemplateBackupRecord: Codable, Sendable {
    let id: UUID
    let name: String
    let body: String
    let localeIdentifier: String
    let channel: String
    let isDefault: Bool
    let createdAt: Date
    let updatedAt: Date
}
