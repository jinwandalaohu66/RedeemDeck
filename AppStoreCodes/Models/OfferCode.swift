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
    var assignedTo: String?
    var notes: String?
    var createdAt: Date = Date()
    var expirationDate: Date?

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

    // MARK: - Actions

    func markAsRedeemed(assignedTo: String? = nil) {
        self.isRedeemed = true
        self.redeemedDate = Date()
        // Only update assignedTo if a new value is explicitly provided
        if let newAssignee = assignedTo {
            self.assignedTo = newAssignee
        }
    }

    func markAsAvailable() {
        self.isRedeemed = false
        self.redeemedDate = nil
    }
}
