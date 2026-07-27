import Foundation
import SwiftData
import Testing
@testable import CodeVault

struct TrackingCoreTests {
    @Test @MainActor
    func disabledTrackingReturnsOriginalURLWithoutCallingBackend() async throws {
        let stub = TrackingClientStub()
        let coordinator = DistributionCoordinator(client: stub)
        let container = try makeInMemoryContainer()
        let code = OfferCode(
            code: "ORIGINAL",
            redemptionURL: "https://apps.apple.com/redeem?ctx=offercodes&id=123&code=ORIGINAL"
        )

        let url = try await coordinator.effectiveURL(
            for: code,
            trackingEnabled: false,
            apiBaseURL: "",
            apiToken: "",
            modelContext: container.mainContext
        )

        #expect(url.absoluteString == code.redemptionURL)
        #expect(stub.createCallCount == 0)
        #expect(code.trackedURL == nil)
    }

    @Test @MainActor
    func registrationPersistsTrackedResourceWithoutMarkingCodeSent() async throws {
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        let stub = TrackingClientStub(link: TrackingLink(
            id: "link-1",
            shortURL: try #require(URL(string: "https://links.example/r/opaque")),
            createdAt: createdAt,
            expiresAt: nil
        ))
        let coordinator = DistributionCoordinator(client: stub)
        let container = try makeInMemoryContainer()
        let code = OfferCode(
            code: "TRACKED",
            redemptionURL: "https://apps.apple.com/redeem?ctx=offercodes&id=123&code=TRACKED"
        )
        container.mainContext.insert(code)

        let url = try await coordinator.effectiveURL(
            for: code,
            trackingEnabled: true,
            apiBaseURL: "https://api.example",
            apiToken: "local-keychain-token",
            modelContext: container.mainContext
        )

        #expect(url.absoluteString == "https://links.example/r/opaque")
        #expect(code.trackingLinkID == "link-1")
        #expect(code.trackedURL == url.absoluteString)
        #expect(code.trackingAPIBaseURL == "https://api.example")
        #expect(code.trackingCreatedAt == createdAt)
        #expect(code.sentAt == nil)
        #expect(code.isAvailable)
    }

    @Test @MainActor
    func persistedTrackedURLIsReusedAcrossConfigurationChanges() async throws {
        let stub = TrackingClientStub()
        let coordinator = DistributionCoordinator(client: stub)
        let container = try makeInMemoryContainer()
        let code = OfferCode(
            code: "REUSE",
            redemptionURL: "https://apps.apple.com/redeem?ctx=offercodes&id=123&code=REUSE"
        )
        code.trackedURL = "https://old.example/r/existing"
        code.trackingLinkID = "existing"
        code.trackingAPIBaseURL = "https://old.example"

        let url = try await coordinator.effectiveURL(
            for: code,
            trackingEnabled: true,
            apiBaseURL: "https://new.example",
            apiToken: "different-token",
            modelContext: container.mainContext
        )

        #expect(url.absoluteString == "https://old.example/r/existing")
        #expect(stub.createCallCount == 0)
        #expect(code.trackingAPIBaseURL == "https://old.example")
    }

    @Test @MainActor
    func failedRegistrationLeavesTrackingStateUntouched() async throws {
        let stub = TrackingClientStub(createError: .offline)
        let coordinator = DistributionCoordinator(client: stub)
        let container = try makeInMemoryContainer()
        let code = OfferCode(
            code: "FAILURE",
            redemptionURL: "https://apps.apple.com/redeem?ctx=offercodes&id=123&code=FAILURE"
        )

        await #expect(throws: TrackingClientStub.StubError.offline) {
            try await coordinator.effectiveURL(
                for: code,
                trackingEnabled: true,
                apiBaseURL: "https://api.example",
                apiToken: "local-keychain-token",
                modelContext: container.mainContext
            )
        }
        #expect(code.trackingLinkID == nil)
        #expect(code.trackedURL == nil)
        #expect(code.trackingAPIBaseURL == nil)
        #expect(code.trackingCreatedAt == nil)
    }

    @Test @MainActor
    func refreshedInteractionBecomesSeenWithoutChangingAvailability() async throws {
        let firstSeenAt = Date(timeIntervalSince1970: 1_810_000_000)
        let lastSeenAt = Date(timeIntervalSince1970: 1_810_000_100)
        let synchronizedAt = Date(timeIntervalSince1970: 1_810_000_200)
        let stub = TrackingClientStub(statuses: [
            TrackingLinkStatus(
                id: "seen-link",
                firstSeenAt: firstSeenAt,
                lastSeenAt: lastSeenAt,
                visitCount: 3
            )
        ])
        let coordinator = DistributionCoordinator(client: stub, now: { synchronizedAt })
        let container = try makeInMemoryContainer()
        let code = OfferCode(
            code: "SEEN",
            redemptionURL: "https://apps.apple.com/redeem?ctx=offercodes&id=123&code=SEEN"
        )
        code.trackingLinkID = "seen-link"
        code.trackingAPIBaseURL = "https://api.example"
        container.mainContext.insert(code)

        try await coordinator.refreshStatus(
            for: code,
            apiToken: "local-keychain-token",
            modelContext: container.mainContext
        )

        #expect(code.firstSeenAt == firstSeenAt)
        #expect(code.lastSeenAt == lastSeenAt)
        #expect(code.trackingVisitCount == 3)
        #expect(code.trackingLastSyncedAt == synchronizedAt)
        #expect(code.isSeen)
        #expect(code.displayStatus == .seen)
        #expect(code.isAvailable)
    }

    @Test @MainActor
    func displayStatusUsesRequiredPrecedence() {
        let code = OfferCode(code: "STATUS", redemptionURL: "https://example.com")
        code.sentAt = Date()
        code.firstSeenAt = Date()
        #expect(code.displayStatus == .seen)

        code.expirationDate = Date(timeIntervalSinceNow: -1)
        #expect(code.displayStatus == .expired)

        code.isRedeemed = true
        #expect(code.displayStatus == .redeemed)
    }

    @Test @MainActor
    func foregroundRefreshBatchesRequestsAtOneHundredLinks() async throws {
        let stub = TrackingClientStub()
        let coordinator = DistributionCoordinator(client: stub)
        let container = try makeInMemoryContainer()
        let codes = (0..<201).map { index in
            let code = OfferCode(
                code: "BATCH-\(index)",
                redemptionURL: "https://apps.apple.com/redeem?id=1&code=BATCH-\(index)"
            )
            code.trackingLinkID = "link-\(index)"
            code.trackingAPIBaseURL = "https://api.example"
            container.mainContext.insert(code)
            return code
        }

        try await coordinator.refreshStatuses(
            for: codes,
            currentAPIBaseURL: "https://unused.example",
            apiToken: "local-keychain-token",
            modelContext: container.mainContext
        )

        #expect(stub.statusBatchSizes == [100, 100, 1])
    }

    @Test @MainActor
    func trackingFieldsPersistAfterDiskReopen() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("tracking.store")
        let timestamp = Date(timeIntervalSince1970: 1_820_000_000)

        do {
            let container = try makeContainer(configuration: ModelConfiguration(url: storeURL))
            let code = OfferCode(code: "PERSIST", redemptionURL: "https://apps.apple.com/redeem?id=1&code=PERSIST")
            code.trackingLinkID = "persisted-link"
            code.trackedURL = "https://links.example/r/persisted"
            code.trackingAPIBaseURL = "https://api.example"
            code.trackingCreatedAt = timestamp
            code.firstSeenAt = timestamp
            code.lastSeenAt = timestamp
            code.trackingVisitCount = 2
            code.trackingLastSyncedAt = timestamp
            container.mainContext.insert(code)
            try container.mainContext.save()
        }

        let reopened = try makeContainer(configuration: ModelConfiguration(url: storeURL))
        let code = try #require(reopened.mainContext.fetch(FetchDescriptor<OfferCode>()).first)
        #expect(code.trackingLinkID == "persisted-link")
        #expect(code.trackedURL == "https://links.example/r/persisted")
        #expect(code.trackingAPIBaseURL == "https://api.example")
        #expect(code.trackingCreatedAt == timestamp)
        #expect(code.firstSeenAt == timestamp)
        #expect(code.lastSeenAt == timestamp)
        #expect(code.trackingVisitCount == 2)
        #expect(code.trackingLastSyncedAt == timestamp)
    }

    @MainActor
    private func makeInMemoryContainer() throws -> ModelContainer {
        try makeContainer(configuration: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @MainActor
    private func makeContainer(configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(
            for: AppRecord.self,
            CodeBatch.self,
            OfferCode.self,
            configurations: configuration
        )
    }
}

@MainActor
private final class TrackingClientStub: TrackingClientProtocol, @unchecked Sendable {
    enum StubError: Error, Equatable {
        case offline
    }

    private let link: TrackingLink?
    private let createError: StubError?
    private let suppliedStatuses: [TrackingLinkStatus]
    private(set) var createCallCount = 0
    private(set) var statusBatchSizes: [Int] = []

    init(
        link: TrackingLink? = nil,
        createError: StubError? = nil,
        statuses: [TrackingLinkStatus] = []
    ) {
        self.link = link
        self.createError = createError
        self.suppliedStatuses = statuses
    }

    func health(configuration: TrackingConfiguration) async throws {}

    func createLink(
        clientId: UUID,
        destinationURL: URL,
        expiresAt: Date?,
        configuration: TrackingConfiguration
    ) async throws -> TrackingLink {
        createCallCount += 1
        if let createError { throw createError }
        guard let link else { throw StubError.offline }
        return link
    }

    func statuses(
        linkIDs: [String],
        configuration: TrackingConfiguration
    ) async throws -> [TrackingLinkStatus] {
        statusBatchSizes.append(linkIDs.count)
        return suppliedStatuses.filter { linkIDs.contains($0.id) }
    }
}
