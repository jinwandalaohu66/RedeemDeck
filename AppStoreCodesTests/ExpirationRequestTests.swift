import Foundation
import Testing
import UserNotifications
@testable import CodeVault

struct ExpirationRequestTests {
    @Test @MainActor
    func schedulesSevenDaysBeforeExpirationAtNine() throws {
        let snapshot = ExpirationNotificationSnapshot(
            batchID: UUID(uuidString: "12345678-1234-1234-1234-1234567890AB")!,
            batchName: "Summer Offer",
            appName: "Example App",
            expirationDate: date(year: 2026, month: 8, day: 20)
        )

        let request = try #require(ExpirationNotificationService.makeRequest(
            for: snapshot,
            calendar: calendar,
            now: date(year: 2026, month: 8, day: 1)
        ))
        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)

        #expect(request.identifier == "codevault.expiration.12345678-1234-1234-1234-1234567890ab")
        #expect(trigger.dateComponents.day == 13)
        #expect(trigger.dateComponents.hour == 9)
        #expect(request.content.body.contains("Summer Offer"))
        #expect(request.content.body.contains("Example App"))
    }

    @Test @MainActor
    func schedulesImmediateWarningInsideWindow() throws {
        let snapshot = ExpirationNotificationSnapshot(
            batchID: UUID(),
            batchName: "Urgent",
            appName: nil,
            expirationDate: date(year: 2026, month: 8, day: 5)
        )

        let request = try #require(ExpirationNotificationService.makeRequest(
            for: snapshot,
            calendar: calendar,
            now: date(year: 2026, month: 8, day: 1, hour: 12)
        ))
        let trigger = try #require(request.trigger as? UNTimeIntervalNotificationTrigger)

        #expect(trigger.timeInterval == 1)
        #expect(request.content.body.contains("Urgent"))
    }

    @Test @MainActor
    func ignoresExpiredBatch() {
        let snapshot = ExpirationNotificationSnapshot(
            batchID: UUID(),
            batchName: "Expired",
            appName: nil,
            expirationDate: date(year: 2026, month: 7, day: 31)
        )

        #expect(ExpirationNotificationService.makeRequest(
            for: snapshot,
            calendar: calendar,
            now: date(year: 2026, month: 8, day: 1)
        ) == nil)
    }

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour
        ))!
    }
}
