import Foundation
import UserNotifications

extension ExpirationNotificationService {
    static func identifier(for batchID: UUID) -> String {
        identifierPrefix + batchID.uuidString.lowercased()
    }

    static func makeRequest(
        for snapshot: ExpirationNotificationSnapshot,
        calendar: Calendar,
        now: Date
    ) -> UNNotificationRequest? {
        guard snapshot.expirationDate > now else { return nil }
        let warningDay = calendar.date(
            byAdding: .day,
            value: -7,
            to: snapshot.expirationDate
        ) ?? snapshot.expirationDate
        let warningDate = calendar.date(
            bySettingHour: 9,
            minute: 0,
            second: 0,
            of: warningDay
        ) ?? warningDay
        let isInsideWarningWindow = warningDate <= now

        let content = UNMutableNotificationContent()
        content.title = String(
            localized: "Codes Expiring Soon",
            comment: "Title for a notification sent before a code batch expires."
        )
        content.body = notificationBody(
            snapshot: snapshot,
            isInsideWarningWindow: isInsideWarningWindow
        )
        content.sound = .default
        content.userInfo[expirationDateUserInfoKey] = snapshot.expirationDate.timeIntervalSince1970

        let trigger: UNNotificationTrigger
        if isInsideWarningWindow {
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        } else {
            let components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: warningDate
            )
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        }

        return UNNotificationRequest(
            identifier: identifier(for: snapshot.batchID),
            content: content,
            trigger: trigger
        )
    }

    static func isExpirationNotification(identifier: String) -> Bool {
        identifier.hasPrefix(identifierPrefix)
    }

    static func representsSameExpiration(
        _ request: UNNotificationRequest,
        as snapshot: ExpirationNotificationSnapshot
    ) -> Bool {
        guard let deliveredExpiration = request.content
            .userInfo[expirationDateUserInfoKey] as? TimeInterval else {
            return true
        }
        return abs(deliveredExpiration - snapshot.expirationDate.timeIntervalSince1970) < 1
    }

    private static func notificationBody(
        snapshot: ExpirationNotificationSnapshot,
        isInsideWarningWindow: Bool
    ) -> String {
        if let appName = snapshot.appName, isInsideWarningWindow {
            return String(localized: "\(snapshot.batchName) for \(appName) expires soon.")
        }
        if let appName = snapshot.appName {
            return String(localized: "\(snapshot.batchName) for \(appName) expires in one week.")
        }
        if isInsideWarningWindow {
            return String(localized: "\(snapshot.batchName) expires soon.")
        }
        return String(localized: "\(snapshot.batchName) expires in one week.")
    }
}
