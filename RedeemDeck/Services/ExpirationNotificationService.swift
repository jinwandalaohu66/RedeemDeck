import Foundation
import UserNotifications

@MainActor
final class ExpirationNotificationService {
    static let shared = ExpirationNotificationService()
    static let identifierPrefix = "redeemdeck.expiration."
    static let expirationDateUserInfoKey = "redeemdeck.expirationDate"

    private let center: ExpirationNotificationCenter
    private let calendar: Calendar
    private let now: () -> Date
    private var operationTail: Task<Void, Never>?
    private var operationSequence = 0

    init(
        center: ExpirationNotificationCenter? = nil,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.center = center ?? SystemExpirationNotificationCenter()
        self.calendar = calendar
        self.now = now
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func schedule(_ snapshot: ExpirationNotificationSnapshot) async {
        await enqueueOperation { [self] in await scheduleImmediately(snapshot) }
    }

    func cancel(batchID: UUID) async {
        await enqueueOperation { [self] in cancelImmediately(batchID: batchID) }
    }

    func reconcile(_ snapshots: [ExpirationNotificationSnapshot]) async {
        await enqueueOperation { [self] in await reconcileImmediately(snapshots) }
    }

    func cancelAll() async {
        await enqueueOperation { [self] in await cancelAllImmediately() }
    }

    private func scheduleImmediately(_ snapshot: ExpirationNotificationSnapshot) async {
        guard let request = Self.makeRequest(for: snapshot, calendar: calendar, now: now()) else {
            cancelImmediately(batchID: snapshot.batchID)
            return
        }
        let delivered = await center.deliveredNotificationRequests().first {
            $0.identifier == request.identifier
        }
        if let delivered, Self.representsSameExpiration(delivered, as: snapshot) { return }

        cancelImmediately(batchID: snapshot.batchID)
        try? await center.add(request)
    }

    private func cancelImmediately(batchID: UUID) {
        let identifier = Self.identifier(for: batchID)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    private func reconcileImmediately(_ snapshots: [ExpirationNotificationSnapshot]) async {
        let expectedIDs = Set(snapshots.compactMap {
            Self.makeRequest(for: $0, calendar: calendar, now: now())?.identifier
        })
        let pendingIDs = Set(await center.pendingRequests().map(\.identifier)
            .filter(Self.isExpirationNotification(identifier:)))
        let deliveredIDs = Set(await center.deliveredNotificationRequests().map(\.identifier)
            .filter(Self.isExpirationNotification(identifier:)))
        let staleIDs = Array(pendingIDs.union(deliveredIDs).subtracting(expectedIDs))
        if !staleIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: staleIDs)
            center.removeDeliveredNotifications(withIdentifiers: staleIDs)
        }
        for snapshot in snapshots
        where !deliveredIDs.contains(Self.identifier(for: snapshot.batchID)) {
            await scheduleImmediately(snapshot)
        }
    }

    private func cancelAllImmediately() async {
        let pending = await center.pendingRequests().map(\.identifier)
            .filter(Self.isExpirationNotification(identifier:))
        let delivered = await center.deliveredNotificationRequests().map(\.identifier)
            .filter(Self.isExpirationNotification(identifier:))
        let identifiers = Array(Set(pending + delivered))
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private func enqueueOperation(
        _ operation: @escaping @MainActor () async -> Void
    ) async {
        operationSequence += 1
        let sequence = operationSequence
        let previous = operationTail
        let task = Task { @MainActor in
            await previous?.value
            await operation()
        }
        operationTail = task
        await task.value
        if operationSequence == sequence { operationTail = nil }
    }
}
