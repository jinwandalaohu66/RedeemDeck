//
//  ExpirationNotificationService.swift
//  AppStoreCodes
//
//  Created by Matteo Comisso on 09/12/2025.
//

import Foundation
import UserNotifications
import SwiftData

final class ExpirationNotificationService {
    static let shared = ExpirationNotificationService()

    private init() {}

    /// Request notification permissions
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            print("Notification authorization error: \(error)")
            return false
        }
    }

    /// Check for expiring codes and schedule notifications
    func checkExpiringCodes(in modelContext: ModelContext) async {
        // Fetch codes expiring within 7 days that are not redeemed
        let now = Date()
        let sevenDaysFromNow = Calendar.current.date(byAdding: .day, value: 7, to: now)!

        let descriptor = FetchDescriptor<OfferCode>(
            predicate: #Predicate<OfferCode> { code in
                code.isRedeemed == false &&
                code.expirationDate != nil
            }
        )

        guard let codes = try? modelContext.fetch(descriptor) else { return }

        // Filter codes expiring within 7 days
        let expiringCodes = codes.filter { code in
            guard let expDate = code.expirationDate else { return false }
            return expDate > now && expDate <= sevenDaysFromNow
        }

        // Group by app and days until expiration
        var expiringToday: [String: Int] = [:]
        var expiringThisWeek: [String: Int] = [:]

        for code in expiringCodes {
            guard let days = code.daysUntilExpiration,
                  let appName = code.app?.name else { continue }

            if days == 0 {
                expiringToday[appName, default: 0] += 1
            } else {
                expiringThisWeek[appName, default: 0] += 1
            }
        }

        // Send notifications
        await sendExpirationNotifications(expiringToday: expiringToday, expiringThisWeek: expiringThisWeek)
    }

    private func sendExpirationNotifications(expiringToday: [String: Int], expiringThisWeek: [String: Int]) async {
        let center = UNUserNotificationCenter.current()

        // Remove old notifications
        center.removeDeliveredNotifications(withIdentifiers: ["expiring-today", "expiring-week"])

        // Notification for codes expiring today
        if !expiringToday.isEmpty {
            let totalToday = expiringToday.values.reduce(0, +)
            let content = UNMutableNotificationContent()
            content.title = "Codes Expiring Today"

            if expiringToday.count == 1, let (appName, count) = expiringToday.first {
                content.body = "\(count) code\(count == 1 ? "" : "s") for \(appName) will expire today."
            } else {
                content.body = "\(totalToday) codes across \(expiringToday.count) apps will expire today."
            }

            content.sound = .default

            let request = UNNotificationRequest(identifier: "expiring-today", content: content, trigger: nil)
            try? await center.add(request)
        }

        // Notification for codes expiring this week (but not today)
        if !expiringThisWeek.isEmpty {
            let totalWeek = expiringThisWeek.values.reduce(0, +)
            let content = UNMutableNotificationContent()
            content.title = "Codes Expiring Soon"

            if expiringThisWeek.count == 1, let (appName, count) = expiringThisWeek.first {
                content.body = "\(count) code\(count == 1 ? "" : "s") for \(appName) will expire within 7 days."
            } else {
                content.body = "\(totalWeek) codes across \(expiringThisWeek.count) apps will expire within 7 days."
            }

            content.sound = .default

            let request = UNNotificationRequest(identifier: "expiring-week", content: content, trigger: nil)
            try? await center.add(request)
        }
    }

    /// Schedule daily check for expiring codes
    func scheduleDailyCheck() {
        // Schedule a daily notification check at 9 AM
        var dateComponents = DateComponents()
        dateComponents.hour = 9
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        let content = UNMutableNotificationContent()
        content.title = "Check Expiring Codes"
        content.body = "Open AppStoreCodes to check for expiring promo codes."
        content.sound = .default

        let request = UNNotificationRequest(identifier: "daily-reminder", content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling daily notification: \(error)")
            }
        }
    }
}
