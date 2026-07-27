import Foundation
import SwiftData

@MainActor
final class DistributionCoordinator {
    static let shared = DistributionCoordinator()

    private let client: any TrackingClientProtocol
    private let now: () -> Date

    init(
        client: (any TrackingClientProtocol)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.client = client ?? TrackingClient()
        self.now = now
    }

    /// Resolves the recipient-facing URL and persists a newly registered link before returning it.
    func effectiveURL(
        for code: OfferCode,
        trackingEnabled: Bool,
        apiBaseURL: String,
        apiToken: String,
        modelContext: ModelContext
    ) async throws -> URL {
        guard let destinationURL = URL(string: code.redemptionURL) else {
            throw TrackingClientError.invalidDestinationURL
        }
        guard trackingEnabled else {
            return destinationURL
        }
        if let trackedURLString = code.trackedURL {
            guard let trackedURL = URL(string: trackedURLString) else {
                throw TrackingClientError.invalidResponse
            }
            return trackedURL
        }

        let configuration = try TrackingConfiguration(
            baseURLString: apiBaseURL,
            apiToken: apiToken
        )
        let link = try await client.createLink(
            clientId: code.id,
            destinationURL: destinationURL,
            expiresAt: code.expirationDate,
            configuration: configuration
        )
        guard link.shortURL.scheme?.lowercased() == "https",
              link.shortURL.host != nil,
              link.shortURL.user == nil,
              link.shortURL.password == nil else {
            throw TrackingClientError.invalidResponse
        }

        let previous = TrackingSnapshot(code: code)
        code.trackingLinkID = link.id
        code.trackedURL = link.shortURL.absoluteString
        code.trackingAPIBaseURL = configuration.baseURL.absoluteString
        code.trackingCreatedAt = link.createdAt
        do {
            try modelContext.save()
        } catch {
            previous.restore(on: code)
            throw error
        }
        return link.shortURL
    }

    func refreshStatus(
        for code: OfferCode,
        apiToken: String,
        modelContext: ModelContext
    ) async throws {
        try await refreshStatuses(
            for: [code],
            currentAPIBaseURL: "",
            apiToken: apiToken,
            modelContext: modelContext
        )
    }

    /// Refreshes all registered codes, grouped by their originating backend and batched to 100 IDs.
    func refreshStatuses(
        for codes: [OfferCode],
        currentAPIBaseURL: String,
        apiToken: String,
        modelContext: ModelContext
    ) async throws {
        let registered = codes.compactMap { code -> RegisteredCode? in
            guard let linkID = code.trackingLinkID else { return nil }
            let baseURL = code.trackingAPIBaseURL ?? currentAPIBaseURL
            guard !baseURL.isEmpty else { return nil }
            return RegisteredCode(code: code, linkID: linkID, baseURL: baseURL)
        }
        guard !registered.isEmpty else { return }

        var received: [String: TrackingLinkStatus] = [:]
        for group in Dictionary(grouping: registered, by: \.baseURL).values {
            let configuration = try TrackingConfiguration(
                baseURLString: group[0].baseURL,
                apiToken: apiToken
            )
            for batch in group.chunked(maxCount: 100) {
                let statuses = try await client.statuses(
                    linkIDs: batch.map(\.linkID),
                    configuration: configuration
                )
                statuses.forEach { received[$0.id] = $0 }
            }
        }

        let snapshots = registered.map { TrackingSnapshot(code: $0.code) }
        let synchronizedAt = now()
        for item in registered {
            guard let status = received[item.linkID] else { continue }
            item.code.firstSeenAt = status.firstSeenAt
            item.code.lastSeenAt = status.lastSeenAt
            item.code.trackingVisitCount = status.visitCount
            item.code.trackingLastSyncedAt = synchronizedAt
        }
        do {
            try modelContext.save()
        } catch {
            zip(registered, snapshots).forEach { item, snapshot in
                snapshot.restore(on: item.code)
            }
            throw error
        }
    }

    private struct RegisteredCode {
        let code: OfferCode
        let linkID: String
        let baseURL: String
    }

    private struct TrackingSnapshot {
        let trackingLinkID: String?
        let trackedURL: String?
        let trackingAPIBaseURL: String?
        let trackingCreatedAt: Date?
        let firstSeenAt: Date?
        let lastSeenAt: Date?
        let trackingVisitCount: Int?
        let trackingLastSyncedAt: Date?

        init(code: OfferCode) {
            trackingLinkID = code.trackingLinkID
            trackedURL = code.trackedURL
            trackingAPIBaseURL = code.trackingAPIBaseURL
            trackingCreatedAt = code.trackingCreatedAt
            firstSeenAt = code.firstSeenAt
            lastSeenAt = code.lastSeenAt
            trackingVisitCount = code.trackingVisitCount
            trackingLastSyncedAt = code.trackingLastSyncedAt
        }

        func restore(on code: OfferCode) {
            code.trackingLinkID = trackingLinkID
            code.trackedURL = trackedURL
            code.trackingAPIBaseURL = trackingAPIBaseURL
            code.trackingCreatedAt = trackingCreatedAt
            code.firstSeenAt = firstSeenAt
            code.lastSeenAt = lastSeenAt
            code.trackingVisitCount = trackingVisitCount
            code.trackingLastSyncedAt = trackingLastSyncedAt
        }
    }
}

private extension Array {
    func chunked(maxCount: Int) -> [[Element]] {
        guard maxCount > 0 else { return [] }
        return stride(from: 0, to: count, by: maxCount).map {
            Array(self[$0..<Swift.min($0 + maxCount, count)])
        }
    }
}
