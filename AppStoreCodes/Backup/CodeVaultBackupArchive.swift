import Foundation

nonisolated struct CodeVaultBackupArchive: Codable, Sendable {
    static let currentVersion = 4

    let schemaVersion: Int
    let createdAt: Date
    let apps: [AppBackupRecord]
    let categories: [CodeCategoryBackupRecord]?
    let batches: [BatchBackupRecord]
    let codes: [CodeBackupRecord]
    let campaigns: [CampaignBackupRecord]
    let recipients: [RecipientBackupRecord]
    let distributions: [DistributionBackupRecord]
    let activities: [ActivityBackupRecord]
    let templates: [TemplateBackupRecord]
}

nonisolated struct CodeCategoryBackupRecord: Codable, Sendable {
    let id: UUID
    let name: String
    let productName: String
    let productID: String?
    let offerReferenceName: String?
    let notes: String?
    let createdAt: Date
    let archivedAt: Date?
    let appID: UUID?
}

nonisolated struct AppBackupRecord: Codable, Sendable {
    let id: UUID
    let name: String
    let appStoreID: String
    let bundleID: String?
    let iconURL: String?
    let appStoreURL: String?
    let developerName: String?
    let appDescription: String?
    let version: String?
    let releaseDate: Date?
    let primaryGenre: String?
    let price: String?
    let currency: String?
    let testFlightURL: String?
    let testFlightNotes: String?
    let notes: String?
    let qrGreeting: String?
    let metadataLastUpdated: Date?
    let createdAt: Date
    let archivedAt: Date?
}

nonisolated struct BatchBackupRecord: Codable, Sendable {
    let id: UUID
    let name: String
    let importDate: Date
    let source: String
    let notes: String?
    let expirationDate: Date?
    let codeKind: String
    let environment: String
    let platform: String
    let appVersion: String?
    let productID: String?
    let offerReferenceName: String?
    let redemptionLimit: Int?
    let archivedAt: Date?
    let appID: UUID?
    let categoryID: UUID?
    let campaignID: UUID?
}

nonisolated struct CodeBackupRecord: Codable, Sendable {
    let id: UUID
    let code: String
    let redemptionURL: String
    let isRedeemed: Bool
    let redeemedDate: Date?
    let sentAt: Date?
    let assignedTo: String?
    let notes: String?
    let createdAt: Date
    let expirationDate: Date?
    let reservedAt: Date?
    let retrievalID: UUID?
    let revokedAt: Date?
    let redemptionCount: Int
    let archivedAt: Date?
    let firstSeenAt: Date?
    let lastSeenAt: Date?
    let trackingVisitCount: Int?
    let trackingLinkID: String?
    let trackedURL: String?
    let trackingAPIBaseURL: String?
    let trackingCreatedAt: Date?
    let trackingLastSyncedAt: Date?
    let appID: UUID?
    let batchID: UUID?
}
