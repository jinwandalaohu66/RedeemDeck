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
    var sentAt: Date?
    var assignedTo: String?
    var notes: String?
    var createdAt: Date = Date()
    var expirationDate: Date?
    var reservedAt: Date?
    var retrievalID: UUID?
    var archivedAt: Date?

    // Stored only so databases and backups from earlier releases remain readable.
    var isRedeemed: Bool = false
    var redeemedDate: Date?
    var redemptionCount: Int = 0
    var revokedAt: Date?
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

    @Relationship(deleteRule: .cascade, inverse: \DistributionRecord.code)
    var distributions: [DistributionRecord]?

    init(code: String, redemptionURL: String, expirationDate: Date? = nil) {
        self.id = UUID()
        self.code = code
        self.redemptionURL = redemptionURL
        self.isRedeemed = false
        self.createdAt = Date()
        self.expirationDate = expirationDate
    }

    var isExpired: Bool {
        guard let expirationDate = expirationDate else { return false }
        return Date() > expirationDate
    }

    var isAvailable: Bool {
        archivedAt == nil
            && revokedAt == nil
            && !isRedeemed
            && !isExpired
            && sentAt == nil
            && reservedAt == nil
    }

    var lifecycleStatus: CodeLifecycleStatus {
        if isExpired { return .expired }
        if sentAt != nil || isRedeemed || revokedAt != nil { return .sent }
        if reservedAt != nil { return .pending }
        return .available
    }

    var isArchived: Bool {
        archivedAt != nil
    }

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
        reservedAt = nil
    }

    func markAsAvailable() {
        sentAt = nil
        reservedAt = nil
        retrievalID = nil
        isRedeemed = false
        redeemedDate = nil
        redemptionCount = 0
        revokedAt = nil
    }

    func reserve(for retrievalID: UUID, at date: Date = Date()) {
        guard isAvailable else { return }
        reservedAt = date
        self.retrievalID = retrievalID
    }

    func restoreToPending(at date: Date = Date()) {
        guard !isExpired, archivedAt == nil, retrievalID != nil else { return }
        sentAt = nil
        reservedAt = date
        isRedeemed = false
        redeemedDate = nil
        redemptionCount = 0
        revokedAt = nil
    }

    func releasePendingReservation() {
        guard sentAt == nil, reservedAt != nil else { return }
        reservedAt = nil
        retrievalID = nil
    }

    func normalizeRetiredLifecycle() {
        if isRedeemed || redeemedDate != nil || redemptionCount > 0 {
            sentAt = sentAt ?? redeemedDate ?? createdAt
            reservedAt = nil
        }
        if let revokedAt {
            archivedAt = archivedAt ?? revokedAt
            reservedAt = nil
            retrievalID = nil
        }
        isRedeemed = false
        redeemedDate = nil
        redemptionCount = 0
        revokedAt = nil
    }
}
