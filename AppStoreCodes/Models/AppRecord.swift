//
//  AppRecord.swift
//  AppStoreCodes
//
//  Created by Matteo Comisso on 08/12/2025.
//

import Foundation
import SwiftData

@Model
final class AppRecord {
    var id: UUID = UUID()
    var name: String = ""
    var appStoreId: String = ""
    var bundleId: String?

    // App Store Metadata
    var iconURL: String?
    var appStoreURL: String?
    var developerName: String?
    var appDescription: String?
    var version: String?
    var releaseDate: Date?
    var primaryGenre: String?
    var price: String?
    var currency: String?

    // TestFlight Info (user-editable)
    var testFlightURL: String?
    var testFlightNotes: String?

    // Custom user notes
    var notes: String?

    // Metadata last updated
    var metadataLastUpdated: Date?

    // Relationships must be optional for CloudKit
    @Relationship(deleteRule: .cascade, inverse: \CodeBatch.app)
    var batches: [CodeBatch]?

    @Relationship(deleteRule: .cascade, inverse: \OfferCode.app)
    var codes: [OfferCode]?

    var createdAt: Date = Date()

    init(name: String, appStoreId: String, bundleId: String? = nil) {
        self.id = UUID()
        self.name = name
        self.appStoreId = appStoreId
        self.bundleId = bundleId
        self.createdAt = Date()
    }

    // MARK: - Computed Properties

    /// Safe accessor for batches
    private var safeBatches: [CodeBatch] {
        batches ?? []
    }

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
        safeCodes.filter(\.isAvailable).count
    }

    var expiredCodesCount: Int {
        safeCodes.filter { $0.isExpired && !$0.isRedeemed }.count
    }

    /// Computed App Store URL if not set manually
    var effectiveAppStoreURL: String {
        appStoreURL ?? "https://apps.apple.com/app/id\(appStoreId)"
    }

    /// Check if metadata has been fetched
    var hasMetadata: Bool {
        metadataLastUpdated != nil
    }
}
