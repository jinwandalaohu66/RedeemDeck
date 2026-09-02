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

    var iconURL: String?
    var appStoreURL: String?

    // Retained for existing stores and backups. The current UI only needs the
    // identity, artwork, App Store URL, notes, and poster greeting above.
    var developerName: String?
    var appDescription: String?
    var version: String?
    var releaseDate: Date?
    var primaryGenre: String?
    var price: String?
    var currency: String?

    var testFlightURL: String?
    var testFlightNotes: String?

    var notes: String?
    var qrGreeting: String?
    var metadataLastUpdated: Date?

    // Optional relationships preserve compatibility with the existing store schema.
    @Relationship(deleteRule: .cascade, inverse: \CodeBatch.app)
    var batches: [CodeBatch]?

    @Relationship(deleteRule: .cascade, inverse: \OfferCode.app)
    var codes: [OfferCode]?

    @Relationship(deleteRule: .cascade, inverse: \CodeCategory.app)
    var categories: [CodeCategory]?

    // Persisted compatibility relationship for stores created before the
    // focused code-library rebuild. No production workflow reads it.
    @Relationship(deleteRule: .cascade, inverse: \Campaign.app)
    var campaigns: [Campaign]?

    var createdAt: Date = Date()
    var archivedAt: Date?

    init(name: String, appStoreId: String, bundleId: String? = nil) {
        self.id = UUID()
        self.name = name
        self.appStoreId = appStoreId
        self.bundleId = bundleId
        self.createdAt = Date()
    }

    var isArchived: Bool {
        archivedAt != nil
    }

    var hasMetadata: Bool {
        metadataLastUpdated != nil
    }
}
