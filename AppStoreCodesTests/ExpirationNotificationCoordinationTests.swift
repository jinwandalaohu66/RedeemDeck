import Foundation
import Testing
import UserNotifications
@testable import CodeVault

struct ExpirationNotificationCoordinationTests {
    @Test @MainActor
    func reconciliationReplacesOnlyOwnedNotifications() async {
        let center = ExpirationNotificationCenterSpy()
        let currentBatchID = UUID()
        let staleID = ExpirationNotificationService.identifier(for: UUID())
        center.pending = [
            request(identifier: staleID),
            request(identifier: "another-feature.reminder"),
        ]
        center.delivered = [request(identifier: staleID)]
        let snapshot = ExpirationNotificationSnapshot(
            batchID: currentBatchID,
            batchName: "Current",
            appName: "Example",
            expirationDate: Date(timeIntervalSince1970: 1_900_000_000)
        )
        let service = ExpirationNotificationService(
            center: center,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )

        await service.reconcile([snapshot])

        #expect(center.added.map(\.identifier) == [
            ExpirationNotificationService.identifier(for: currentBatchID)
        ])
        #expect(center.removedPending.contains(staleID))
        #expect(!center.removedPending.contains("another-feature.reminder"))
    }

    @Test @MainActor
    func refreshDoesNotRepeatDeliveredExpiration() async {
        let center = ExpirationNotificationCenterSpy()
        let snapshot = ExpirationNotificationSnapshot(
            batchID: UUID(),
            batchName: "Promo",
            appName: nil,
            expirationDate: Date(timeIntervalSince1970: 1_900_000_000)
        )
        center.delivered = [request(for: snapshot)]
        let service = ExpirationNotificationService(
            center: center,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )

        await service.schedule(snapshot)

        #expect(center.added.isEmpty)
        #expect(center.removedDelivered.isEmpty)
    }

    @Test @MainActor
    func changedExpirationReplacesDeliveredRequest() async {
        let center = ExpirationNotificationCenterSpy()
        let batchID = UUID()
        let old = ExpirationNotificationSnapshot(
            batchID: batchID,
            batchName: "Promo",
            appName: nil,
            expirationDate: Date(timeIntervalSince1970: 1_900_000_000)
        )
        let updated = ExpirationNotificationSnapshot(
            batchID: batchID,
            batchName: "Promo",
            appName: nil,
            expirationDate: Date(timeIntervalSince1970: 1_910_000_000)
        )
        center.delivered = [request(for: old)]
        let service = ExpirationNotificationService(
            center: center,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )

        await service.schedule(updated)

        let identifier = ExpirationNotificationService.identifier(for: batchID)
        #expect(center.added.map(\.identifier) == [identifier])
        #expect(center.removedDelivered == [identifier])
    }

    @MainActor
    private func request(identifier: String) -> UNNotificationRequest {
        UNNotificationRequest(
            identifier: identifier,
            content: UNMutableNotificationContent(),
            trigger: nil
        )
    }

    @MainActor
    private func request(
        for snapshot: ExpirationNotificationSnapshot
    ) -> UNNotificationRequest {
        ExpirationNotificationService.makeRequest(
            for: snapshot,
            calendar: .current,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )!
    }
}

@MainActor
private final class ExpirationNotificationCenterSpy: ExpirationNotificationCenter {
    var pending: [UNNotificationRequest] = []
    var delivered: [UNNotificationRequest] = []
    var added: [UNNotificationRequest] = []
    var removedPending: [String] = []
    var removedDelivered: [String] = []

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { true }

    func add(_ request: UNNotificationRequest) async throws {
        added.append(request)
    }

    func pendingRequests() async -> [UNNotificationRequest] { pending }

    func deliveredNotificationRequests() async -> [UNNotificationRequest] { delivered }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedPending.append(contentsOf: identifiers)
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        removedDelivered.append(contentsOf: identifiers)
    }
}
