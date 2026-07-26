import Foundation
import Testing
import UserNotifications
@testable import CodeVault

struct ExpirationNotificationServiceTests {
    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0
    ) -> Date {
        utcCalendar().date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour
        ))!
    }

    @Test @MainActor
    func buildsAStableRequestSevenDaysBeforeExpiration() throws {
        let batchID = UUID(uuidString: "12345678-1234-1234-1234-1234567890AB")!
        let snapshot = ExpirationNotificationSnapshot(
            batchID: batchID,
            batchName: "Summer Offer",
            appName: "Example App",
            expirationDate: date(year: 2026, month: 8, day: 20)
        )

        let request = try #require(ExpirationNotificationService.makeRequest(
            for: snapshot,
            calendar: utcCalendar(),
            now: date(year: 2026, month: 8, day: 1)
        ))
        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)

        #expect(request.identifier == "codevault.expiration.12345678-1234-1234-1234-1234567890ab")
        #expect(trigger.dateComponents.year == 2026)
        #expect(trigger.dateComponents.month == 8)
        #expect(trigger.dateComponents.day == 13)
        #expect(trigger.dateComponents.hour == 9)
        #expect(trigger.dateComponents.minute == 0)
        #expect(request.content.body.contains("Summer Offer"))
        #expect(request.content.body.contains("Example App"))
    }

    @Test @MainActor
    func schedulesAnImmediateWarningWhenImportedInsideSevenDays() throws {
        let snapshot = ExpirationNotificationSnapshot(
            batchID: UUID(),
            batchName: "Urgent Offer",
            appName: nil,
            expirationDate: date(year: 2026, month: 8, day: 5)
        )

        let request = try #require(ExpirationNotificationService.makeRequest(
            for: snapshot,
            calendar: utcCalendar(),
            now: date(year: 2026, month: 8, day: 1, hour: 12)
        ))
        let trigger = try #require(request.trigger as? UNTimeIntervalNotificationTrigger)

        #expect(trigger.timeInterval == 1)
        #expect(request.content.body == "Urgent Offer expires soon.")
    }

    @Test @MainActor
    func doesNotScheduleAnExpiredImport() {
        let snapshot = ExpirationNotificationSnapshot(
            batchID: UUID(),
            batchName: "Expired Offer",
            appName: nil,
            expirationDate: date(year: 2026, month: 7, day: 31)
        )

        #expect(ExpirationNotificationService.makeRequest(
            for: snapshot,
            calendar: utcCalendar(),
            now: date(year: 2026, month: 8, day: 1)
        ) == nil)
    }

    @Test @MainActor
    func reconcilesAndCancelsOnlyOwnedBatchNotifications() async {
        let center = ExpirationNotificationCenterSpy()
        let currentBatchID = UUID()
        let staleBatchID = UUID()
        let staleIdentifier = ExpirationNotificationService.identifier(for: staleBatchID)
        center.pending = [
            notificationRequest(identifier: staleIdentifier),
            notificationRequest(identifier: "another-feature.reminder")
        ]
        center.delivered = [
            notificationRequest(identifier: staleIdentifier),
            notificationRequest(identifier: "another-feature.delivered")
        ]
        let snapshot = ExpirationNotificationSnapshot(
            batchID: currentBatchID,
            batchName: "Current Offer",
            appName: "Example App",
            expirationDate: date(year: 2026, month: 9, day: 1)
        )
        let service = ExpirationNotificationService(
            center: center,
            calendar: utcCalendar(),
            now: { self.date(year: 2026, month: 8, day: 1) }
        )

        await service.reconcile([snapshot])

        #expect(center.added.map(\.identifier) == [
            ExpirationNotificationService.identifier(for: currentBatchID)
        ])
        #expect(center.removedPending.contains(staleIdentifier))
        #expect(!center.removedPending.contains("another-feature.reminder"))

        await service.cancel(batchID: currentBatchID)
        #expect(center.removedPending.contains(
            ExpirationNotificationService.identifier(for: currentBatchID)
        ))

        await service.cancelAll()
        #expect(center.removedDelivered.contains(staleIdentifier))
        #expect(!center.removedDelivered.contains("another-feature.delivered"))
    }

    @Test @MainActor
    func cancellationQueuedDuringAnAddWinsAfterTheAddCompletes() async {
        let center = ExpirationNotificationCenterSpy()
        center.suspendAdds = true
        let batchID = UUID()
        let snapshot = ExpirationNotificationSnapshot(
            batchID: batchID,
            batchName: "Promo Codes",
            appName: "Example App",
            expirationDate: date(year: 2026, month: 9, day: 1)
        )
        let service = ExpirationNotificationService(
            center: center,
            calendar: utcCalendar(),
            now: { self.date(year: 2026, month: 8, day: 1) }
        )

        let scheduleTask = Task {
            await service.schedule(snapshot)
        }
        while !center.isAddSuspended {
            await Task.yield()
        }
        let cancelTask = Task {
            await service.cancel(batchID: batchID)
        }

        center.resumeAdd()
        await scheduleTask.value
        await cancelTask.value

        let identifier = ExpirationNotificationService.identifier(for: batchID)
        #expect(center.added.map(\.identifier) == [identifier])
        #expect(center.removedPending.last == identifier)
        #expect(center.removedDelivered.last == identifier)
    }

    @Test @MainActor
    func reconciliationDoesNotRepeatAnAlreadyDeliveredWarning() async {
        let center = ExpirationNotificationCenterSpy()
        let batchID = UUID()
        let snapshot = ExpirationNotificationSnapshot(
            batchID: batchID,
            batchName: "Promo Codes",
            appName: nil,
            expirationDate: date(year: 2026, month: 8, day: 5)
        )
        center.delivered = [notificationRequest(for: snapshot)]
        let service = ExpirationNotificationService(
            center: center,
            calendar: utcCalendar(),
            now: { self.date(year: 2026, month: 8, day: 1) }
        )

        await service.reconcile([snapshot])

        #expect(center.added.isEmpty)
        #expect(center.removedDelivered.isEmpty)
    }

    @Test @MainActor
    func directRefreshDoesNotRepeatAnAlreadyDeliveredWarning() async {
        let center = ExpirationNotificationCenterSpy()
        let snapshot = ExpirationNotificationSnapshot(
            batchID: UUID(),
            batchName: "Promo Codes",
            appName: nil,
            expirationDate: date(year: 2026, month: 8, day: 5)
        )
        center.delivered = [notificationRequest(for: snapshot)]
        let service = ExpirationNotificationService(
            center: center,
            calendar: utcCalendar(),
            now: { self.date(year: 2026, month: 8, day: 1) }
        )

        await service.schedule(snapshot)

        #expect(center.added.isEmpty)
        #expect(center.removedDelivered.isEmpty)
    }

    @Test @MainActor
    func directRefreshSchedulesWhenExpirationChanges() async {
        let center = ExpirationNotificationCenterSpy()
        let batchID = UUID()
        let oldSnapshot = ExpirationNotificationSnapshot(
            batchID: batchID,
            batchName: "Promo Codes",
            appName: nil,
            expirationDate: date(year: 2026, month: 8, day: 5)
        )
        let updatedSnapshot = ExpirationNotificationSnapshot(
            batchID: batchID,
            batchName: "Promo Codes",
            appName: nil,
            expirationDate: date(year: 2026, month: 8, day: 20)
        )
        center.delivered = [notificationRequest(for: oldSnapshot)]
        let service = ExpirationNotificationService(
            center: center,
            calendar: utcCalendar(),
            now: { self.date(year: 2026, month: 8, day: 1) }
        )

        await service.schedule(updatedSnapshot)

        let identifier = ExpirationNotificationService.identifier(for: batchID)
        #expect(center.added.map(\.identifier) == [identifier])
        #expect(center.removedDelivered == [identifier])
    }

    private func notificationRequest(identifier: String) -> UNNotificationRequest {
        UNNotificationRequest(
            identifier: identifier,
            content: UNMutableNotificationContent(),
            trigger: nil
        )
    }


    @MainActor
    private func notificationRequest(
        for snapshot: ExpirationNotificationSnapshot
    ) -> UNNotificationRequest {
        ExpirationNotificationService.makeRequest(
            for: snapshot,
            calendar: utcCalendar(),
            now: date(year: 2026, month: 8, day: 1)
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
    var suspendAdds = false
    private(set) var isAddSuspended = false
    private var addContinuation: CheckedContinuation<Void, Never>?

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        true
    }

    func add(_ request: UNNotificationRequest) async throws {
        added.append(request)
        guard suspendAdds else { return }

        isAddSuspended = true
        await withCheckedContinuation { continuation in
            addContinuation = continuation
        }
        isAddSuspended = false
    }

    func pendingRequests() async -> [UNNotificationRequest] {
        pending
    }

    func deliveredNotificationRequests() async -> [UNNotificationRequest] {
        delivered
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedPending.append(contentsOf: identifiers)
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        removedDelivered.append(contentsOf: identifiers)
    }

    func resumeAdd() {
        addContinuation?.resume()
        addContinuation = nil
    }
}
