//
//  OfferCode.swift
//  AppStoreCodes
//
//  Created by Matteo Comisso on 08/12/2025.
//

import Foundation
import SwiftData

@Model
final class OfferCode {
    var id: UUID = UUID()
    var code: String = ""
    var redemptionURL: String = ""
    var isRedeemed: Bool = false
    var redeemedDate: Date?
    var sentAt: Date?
    var assignedTo: String?
    var notes: String?
    var createdAt: Date = Date()
    var expirationDate: Date?
    var trackingLinkID: String?
    var trackedURL: String?
    var trackingAPIBaseURL: String?
    var trackingCreatedAt: Date?
    var firstSeenAt: Date?
    var lastSeenAt: Date?
    var trackingVisitCount: Int?
    var trackingLastSyncedAt: Date?

    var app: AppRecord?
    var batch: CodeBatch?

    init(code: String, redemptionURL: String, expirationDate: Date? = nil) {
        self.id = UUID()
        self.code = code
        self.redemptionURL = redemptionURL
        self.isRedeemed = false
        self.createdAt = Date()
        self.expirationDate = expirationDate
    }

    /// Check if the code has expired
    var isExpired: Bool {
        guard let expirationDate = expirationDate else { return false }
        return Date() > expirationDate
    }

    /// Days until expiration (negative if expired)
    var daysUntilExpiration: Int? {
        guard let expirationDate = expirationDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: expirationDate).day
    }

    /// A code is available only until it has been sent, redeemed, or expired.
    var isAvailable: Bool {
        !isRedeemed && sentAt == nil && !isExpired
    }

    /// A redirect request is informational and does not change availability.
    var isSeen: Bool {
        firstSeenAt != nil || (trackingVisitCount ?? 0) > 0
    }

    /// The presentation precedence used by code lists and details.
    var displayStatus: OfferCodeDisplayStatus {
        if isRedeemed { return .redeemed }
        if isExpired { return .expired }
        if isSeen { return .seen }
        if sentAt != nil { return .sent }
        return .available
    }

    // MARK: - Actions

    func markAsSent(
        at sentAt: Date = Date(),
        assignedTo: String? = nil,
        notes: String? = nil
    ) {
        self.sentAt = sentAt
        if let assignedTo {
            self.assignedTo = assignedTo
        }
        if let notes {
            self.notes = notes
        }
    }

    func markAsRedeemed(assignedTo: String? = nil) {
        self.isRedeemed = true
        self.redeemedDate = Date()
        // Only update assignedTo if a new value is explicitly provided
        if let newAssignee = assignedTo {
            self.assignedTo = newAssignee
        }
    }

    func markAsUnsent() {
        self.sentAt = nil
    }

    func markAsUnredeemed() {
        self.isRedeemed = false
        self.redeemedDate = nil
    }

    func markAsAvailable() {
        markAsUnredeemed()
        self.sentAt = nil
    }
}

enum OfferCodeDisplayStatus: String, CaseIterable, Sendable {
    case redeemed
    case expired
    case seen
    case sent
    case available
}
