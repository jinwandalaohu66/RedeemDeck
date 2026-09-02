//
//  CodeBatch.swift
//  AppStoreCodes
//
//  Created by Matteo Comisso on 08/12/2025.
//

import Foundation
import SwiftData

nonisolated enum ImportSource: String, Codable, Sendable {
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
    var codeKindRawValue: String = CodeKind.unknown.rawValue
    var environmentRawValue: String = CodeEnvironment.production.rawValue
    var platformRawValue: String = AppPlatform.iOS.rawValue
    var appVersion: String?
    var productID: String?
    var offerReferenceName: String?
    // Retained only when reading and writing backups from earlier releases.
    var redemptionLimit: Int?
    var archivedAt: Date?

    var app: AppRecord?
    var category: CodeCategory?
    // Persisted compatibility relationship for older backups and stores.
    var campaign: Campaign?

    // Optional relationship preserves compatibility with the existing store schema.
    @Relationship(deleteRule: .cascade, inverse: \OfferCode.batch)
    var codes: [OfferCode]?

    var source: ImportSource {
        get { ImportSource(rawValue: sourceRawValue) ?? .csv }
        set { sourceRawValue = newValue.rawValue }
    }

    var codeKind: CodeKind {
        get { CodeKind(rawValue: codeKindRawValue) ?? .unknown }
        set { codeKindRawValue = newValue.rawValue }
    }

    var environment: CodeEnvironment {
        get { CodeEnvironment(rawValue: environmentRawValue) ?? .production }
        set { environmentRawValue = newValue.rawValue }
    }

    var platform: AppPlatform {
        get { AppPlatform(rawValue: platformRawValue) ?? .iOS }
        set { platformRawValue = newValue.rawValue }
    }

    init(name: String, source: ImportSource, notes: String? = nil, expirationDate: Date? = nil) {
        self.id = UUID()
        self.name = name
        self.importDate = Date()
        self.sourceRawValue = source.rawValue
        self.notes = notes
        self.expirationDate = expirationDate
    }

    var isArchived: Bool {
        archivedAt != nil
    }

    func updateExpirationDate(_ expirationDate: Date?) {
        self.expirationDate = expirationDate
        for code in codes ?? [] {
            code.expirationDate = expirationDate
        }
    }
}
