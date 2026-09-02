import Foundation
import UserNotifications

nonisolated struct ExpirationNotificationSnapshot: Equatable, Sendable {
    let batchID: UUID
    let batchName: String
    let appName: String?
    let expirationDate: Date
}

protocol ExpirationNotificationCenter: AnyObject {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func pendingRequests() async -> [UNNotificationRequest]
    func deliveredNotificationRequests() async -> [UNNotificationRequest]
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func removeDeliveredNotifications(withIdentifiers identifiers: [String])
}

final class SystemExpirationNotificationCenter: ExpirationNotificationCenter {
    private let center: UNUserNotificationCenter
    private let foregroundDelegate: ForegroundNotificationDelegate

    init(center: UNUserNotificationCenter = .current()) {
        let delegate = ForegroundNotificationDelegate()
        self.center = center
        foregroundDelegate = delegate
        center.delegate = delegate
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await center.requestAuthorization(options: options)
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    func pendingRequests() async -> [UNNotificationRequest] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests {
                continuation.resume(returning: $0)
            }
        }
    }

    func deliveredNotificationRequests() async -> [UNNotificationRequest] {
        await withCheckedContinuation { continuation in
            center.getDeliveredNotifications {
                continuation.resume(returning: $0.map(\.request))
            }
        }
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}

private final class ForegroundNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
