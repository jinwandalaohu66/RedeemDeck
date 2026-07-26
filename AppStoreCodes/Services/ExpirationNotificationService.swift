//
//  ExpirationNotificationService.swift
//  AppStoreCodes
//
//  Created by Matteo Comisso on 09/12/2025.
//

import Foundation
import UserNotifications

struct ExpirationNotificationSnapshot: Equatable, Sendable {
    let batchID: UUID
    let batchName: String
    let appName: String?
    let expirationDate: Date

    init(
        batchID: UUID,
        batchName: String,
        appName: String?,
        expirationDate: Date
    ) {
        self.batchID = batchID
        self.batchName = batchName
        self.appName = appName
        self.expirationDate = expirationDate
    }

    init?(batch: CodeBatch) {
        guard batch.availableCodesCount > 0,
              let expirationDate = batch.expirationDate else { return nil }

        self.batchID = batch.id
        self.batchName = batch.name
        self.appName = batch.app?.name
        self.expirationDate = expirationDate
    }
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
        let foregroundDelegate = ForegroundNotificationDelegate()
        self.center = center
        self.foregroundDelegate = foregroundDelegate
        center.delegate = foregroundDelegate
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await center.requestAuthorization(options: options)
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    func pendingRequests() async -> [UNNotificationRequest] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests)
            }
        }
    }

    func deliveredNotificationRequests() async -> [UNNotificationRequest] {
        await withCheckedContinuation { continuation in
            center.getDeliveredNotifications { notifications in
                continuation.resume(returning: notifications.map(\.request))
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

@MainActor
final class ExpirationNotificationService {
    static let shared = ExpirationNotificationService()

    static let identifierPrefix = "codevault.expiration."
    static let expirationDateUserInfoKey = "codevault.expirationDate"

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
            print("Notification authorization error: \(error)")
            return false
        }
    }

    func schedule(_ snapshot: ExpirationNotificationSnapshot) async {
        await enqueueOperation { [self] in
            await scheduleImmediately(snapshot)
        }
    }

    func cancel(batchID: UUID) async {
        await enqueueOperation { [self] in
            cancelImmediately(batchID: batchID)
        }
    }

    func reconcile(_ snapshots: [ExpirationNotificationSnapshot]) async {
        await enqueueOperation { [self] in
            await reconcileImmediately(snapshots)
        }
    }

    func cancelAll() async {
        await enqueueOperation { [self] in
            await cancelAllImmediately()
        }
    }

    private func scheduleImmediately(_ snapshot: ExpirationNotificationSnapshot) async {
        guard let request = Self.makeRequest(
            for: snapshot,
            calendar: calendar,
            now: now()
        ) else {
            cancelImmediately(batchID: snapshot.batchID)
            return
        }

        let deliveredRequest = await center.deliveredNotificationRequests().first {
            $0.identifier == request.identifier
        }
        if let deliveredRequest,
           Self.representsSameExpiration(deliveredRequest, as: snapshot) {
            return
        }

        cancelImmediately(batchID: snapshot.batchID)
        do {
            try await center.add(request)
        } catch {
            print("Expiration notification scheduling error: \(error)")
        }
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
        let ownedPendingIDs = Set(await center.pendingRequests()
            .map(\.identifier)
            .filter(Self.isExpirationNotification(identifier:)))
        let ownedDeliveredIDs = Set(await center.deliveredNotificationRequests()
            .map(\.identifier)
            .filter(Self.isExpirationNotification(identifier:)))
        let staleIDs = Array(
            ownedPendingIDs.union(ownedDeliveredIDs).subtracting(expectedIDs)
        )

        if !staleIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: staleIDs)
            center.removeDeliveredNotifications(withIdentifiers: staleIDs)
        }

        for snapshot in snapshots {
            let identifier = Self.identifier(for: snapshot.batchID)
            guard !ownedDeliveredIDs.contains(identifier) else { continue }
            await scheduleImmediately(snapshot)
        }
    }

    private func cancelAllImmediately() async {
        let pendingIDs = await center.pendingRequests()
            .map(\.identifier)
            .filter(Self.isExpirationNotification(identifier:))
        let deliveredIDs = await center.deliveredNotificationRequests()
            .map(\.identifier)
            .filter(Self.isExpirationNotification(identifier:))
        let identifiers = Array(Set(pendingIDs + deliveredIDs))

        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private func enqueueOperation(
        _ operation: @escaping @MainActor () async -> Void
    ) async {
        operationSequence += 1
        let sequence = operationSequence
        let previousOperation = operationTail
        let operationTask = Task { @MainActor in
            await previousOperation?.value
            await operation()
        }
        operationTail = operationTask
        await operationTask.value

        if operationSequence == sequence {
            operationTail = nil
        }
    }

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
            comment: "Title for a notification sent before an imported batch of offer codes expires."
        )
        if let appName = snapshot.appName, isInsideWarningWindow {
            content.body = String(
                localized: "\(snapshot.batchName) for \(appName) expires soon.",
                comment: "Immediate expiration notification body. The first value is the import name and the second is the app name."
            )
        } else if let appName = snapshot.appName {
            content.body = String(
                localized: "\(snapshot.batchName) for \(appName) expires in one week.",
                comment: "Expiration notification body. The first value is the import name and the second is the app name."
            )
        } else if isInsideWarningWindow {
            content.body = String(
                localized: "\(snapshot.batchName) expires soon.",
                comment: "Immediate expiration notification body. The value is the import name."
            )
        } else {
            content.body = String(
                localized: "\(snapshot.batchName) expires in one week.",
                comment: "Expiration notification body. The value is the import name."
            )
        }
        content.sound = .default
        content.userInfo[expirationDateUserInfoKey] = snapshot.expirationDate.timeIntervalSince1970

        let trigger: UNNotificationTrigger
        if !isInsideWarningWindow {
            let components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: warningDate
            )
            trigger = UNCalendarNotificationTrigger(
                dateMatching: components,
                repeats: false
            )
        } else {
            // An import made inside the seven-day warning window should still
            // notify instead of silently missing its warning date.
            trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: 1,
                repeats: false
            )
        }

        return UNNotificationRequest(
            identifier: identifier(for: snapshot.batchID),
            content: content,
            trigger: trigger
        )
    }

    private static func isExpirationNotification(identifier: String) -> Bool {
        identifier.hasPrefix(identifierPrefix)
    }

    private static func representsSameExpiration(
        _ request: UNNotificationRequest,
        as snapshot: ExpirationNotificationSnapshot
    ) -> Bool {
        guard let deliveredExpiration = request.content.userInfo[expirationDateUserInfoKey]
            as? TimeInterval else {
            // Older Code Vault versions did not record the occurrence. Avoid
            // repeating an alert that may already have fired.
            return true
        }

        return abs(deliveredExpiration - snapshot.expirationDate.timeIntervalSince1970) < 1
    }
}
