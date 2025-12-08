//
//  CodeBatch.swift
//  AppStoreCodes
//
//  Created by Matteo Comisso on 08/12/2025.
//

import Foundation
import SwiftData

enum ImportSource: String, Codable {
    case csv
    case api
}

@Model
final class CodeBatch {
    var id: UUID = UUID()
    var name: String = ""
    var importDate: Date = Date()
    var sourceRawValue: String = ImportSource.csv.rawValue
    var notes: String?
    var expirationDate: Date?

    var app: AppRecord?

    // Relationship must be optional for CloudKit
    @Relationship(deleteRule: .cascade, inverse: \OfferCode.batch)
    var codes: [OfferCode]?

    /// Computed property to get/set the source enum
    var source: ImportSource {
        get { ImportSource(rawValue: sourceRawValue) ?? .csv }
        set { sourceRawValue = newValue.rawValue }
    }

    init(name: String, source: ImportSource, notes: String? = nil, expirationDate: Date? = nil) {
        self.id = UUID()
        self.name = name
        self.importDate = Date()
        self.sourceRawValue = source.rawValue
        self.notes = notes
        self.expirationDate = expirationDate
    }

    // MARK: - Computed Properties

    /// Safe accessor for codes
    private var safeCodes: [OfferCode] {
        codes ?? []
    }

    var totalCodesCount: Int {
        safeCodes.count
    }

    var redeemedCodesCount: Int {
        safeCodes.filter { $0.isRedeemed }.count
    }

    var availableCodesCount: Int {
        safeCodes.filter { !$0.isRedeemed && !$0.isExpired }.count
    }

    var expiredCodesCount: Int {
        safeCodes.filter { $0.isExpired && !$0.isRedeemed }.count
    }

    /// Check if this batch has expired
    var isExpired: Bool {
        guard let expirationDate = expirationDate else { return false }
        return Date() > expirationDate
    }

    /// Days until expiration
    var daysUntilExpiration: Int? {
        guard let expirationDate = expirationDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: expirationDate).day
    }
}
