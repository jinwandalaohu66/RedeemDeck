import Foundation

nonisolated struct AppSummary: Identifiable, Sendable {
    let id: UUID
    let name: String
    let appStoreID: String
    let iconURL: String?
    let appStoreURL: String?
    let qrGreeting: String?

    init(
        id: UUID,
        name: String,
        appStoreID: String,
        iconURL: String?,
        appStoreURL: String?,
        qrGreeting: String? = nil
    ) {
        self.id = id
        self.name = name
        self.appStoreID = appStoreID
        self.iconURL = iconURL
        self.appStoreURL = appStoreURL
        self.qrGreeting = qrGreeting
    }

    var effectiveAppStoreURL: String {
        appStoreURL ?? "https://apps.apple.com/app/id\(appStoreID)"
    }
}

extension AppSummary: Hashable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

nonisolated struct RetrievalHistorySummary: Identifiable, Sendable {
    let id: UUID
    let categoryName: String
    let count: Int
    let pendingCount: Int
    let sentCount: Int
    let expiredCount: Int
    let createdAt: Date
}

nonisolated struct CodeCategorySummary: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let productName: String
    let productID: String?
    let offerReferenceName: String?
    let notes: String?
    let availableCount: Int
    let totalCount: Int
    let expiringCount: Int

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

nonisolated struct CodeCategoryCodeSnapshot: Sendable {
    let rows: [CodeRowSummary]
    let matchingCount: Int
    let availableCount: Int
    let totalCount: Int

    static let empty = CodeCategoryCodeSnapshot(
        rows: [],
        matchingCount: 0,
        availableCount: 0,
        totalCount: 0
    )
}

nonisolated struct CodeCategoryCodeLoadRequest: Hashable, Sendable {
    let revision: Int
    let searchText: String
    let filter: CodeBrowserFilter
    let limit: Int
}

nonisolated struct CodeRowSummary: Identifiable, Hashable, Sendable {
    let id: UUID
    let code: String
    let redemptionURL: String
    let status: CodeLifecycleStatus
    let expirationDate: Date?
    let notes: String?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
