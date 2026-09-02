import Foundation
import SwiftData

nonisolated struct PreparedCode: Sendable, Identifiable {
    let id: UUID
    let code: String
    let redemptionURL: String
    let status: CodeLifecycleStatus
    let expirationDate: Date?
}

nonisolated struct PreparedCodeSelection: Sendable, Identifiable {
    let id: UUID
    let appID: UUID
    let appName: String
    let appIconURL: String?
    let appGreeting: String?
    let categoryID: UUID
    let categoryName: String
    let productName: String
    let createdAt: Date
    let codes: [PreparedCode]

    var pendingCount: Int {
        codes.count { $0.status == .pending }
    }

    var isPending: Bool {
        pendingCount > 0
    }
}

nonisolated enum RedeemDeckRepositoryError: LocalizedError, Sendable {
    case appNotFound
    case categoryNotFound
    case batchNotFound
    case codeNotFound
    case selectionNotFound
    case invalidQuantity
    case noAvailableCode
    case insufficientAvailable(Int)
    case codeUnavailable

    var errorDescription: String? {
        switch self {
        case .appNotFound:
            String(localized: "The selected app no longer exists.")
        case .categoryNotFound:
            String(localized: "The selected code category no longer exists.")
        case .batchNotFound:
            String(localized: "The selected batch no longer exists.")
        case .codeNotFound:
            String(localized: "The selected code no longer exists.")
        case .selectionNotFound:
            String(localized: "This retrieval is no longer available.")
        case .invalidQuantity:
            String(localized: "Enter a valid quantity.")
        case .noAvailableCode:
            String(localized: "There are no available codes for this selection.")
        case .insufficientAvailable(let count):
            String(localized: "Only \(count) codes are currently available.")
        case .codeUnavailable:
            String(localized: "This code is no longer available.")
        }
    }
}

@ModelActor
actor RedeemDeckRepository {
    func reserveCodes(categoryID: UUID, quantity: Int) throws -> PreparedCodeSelection {
        guard quantity > 0 else { throw RedeemDeckRepositoryError.invalidQuantity }
        guard let category = try fetchCategory(id: categoryID),
              !category.isArchived,
              category.app != nil else {
            throw RedeemDeckRepositoryError.categoryNotFound
        }

        let candidates = (category.batches ?? [])
            .filter { !$0.isArchived }
            .flatMap { $0.codes ?? [] }
            .filter { !$0.isArchived && $0.isAvailable }
            .sorted(by: Self.shouldSelectBefore)
        guard !candidates.isEmpty else {
            throw RedeemDeckRepositoryError.noAvailableCode
        }
        guard candidates.count >= quantity else {
            throw RedeemDeckRepositoryError.insufficientAvailable(candidates.count)
        }

        let retrievalID = UUID()
        let reservationDate = Date()
        let selected = Array(candidates.prefix(quantity))
        for code in selected {
            code.reserve(for: retrievalID, at: reservationDate)
        }
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
        return try makeSelection(id: retrievalID, codes: selected)
    }

    func loadSelection(id: UUID) throws -> PreparedCodeSelection? {
        let codes = try modelContext.fetch(FetchDescriptor<OfferCode>(
            predicate: #Predicate { $0.retrievalID == id },
            sortBy: [SortDescriptor(\.createdAt)]
        ))
        guard !codes.isEmpty else { return nil }
        return try makeSelection(id: id, codes: codes)
    }

    func loadPendingSelections() throws -> [PreparedCodeSelection] {
        let candidates = try modelContext.fetch(FetchDescriptor<OfferCode>(
            predicate: #Predicate { $0.retrievalID != nil }
        ))
        let pendingCodes = candidates
            .filter { !$0.isArchived && $0.lifecycleStatus == .pending }
            .sorted { ($0.reservedAt ?? .distantPast) > ($1.reservedAt ?? .distantPast) }
        let grouped = Dictionary(grouping: pendingCodes) { $0.retrievalID }
        return try grouped.compactMap { id, codes in
            guard let id else { return nil }
            return try makeSelection(id: id, codes: codes)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    func markSelectionSent(id: UUID, at date: Date = Date()) throws -> PreparedCodeSelection {
        guard let selection = try loadSelection(id: id) else {
            throw RedeemDeckRepositoryError.selectionNotFound
        }
        let codes = try fetchCodes(retrievalID: id)
        var changedCount = 0
        for code in codes where code.lifecycleStatus == .pending || code.lifecycleStatus == .available {
            code.markAsSent(at: date)
            changedCount += 1
        }
        if changedCount > 0 {
            try modelContext.save()
        }
        return try loadSelection(id: id) ?? selection
    }

    @discardableResult
    func markCodeSent(id: UUID, at date: Date = Date()) throws -> CodeLifecycleStatus {
        guard let code = try fetchCode(id: id) else {
            throw RedeemDeckRepositoryError.codeNotFound
        }
        guard code.lifecycleStatus == .available || code.lifecycleStatus == .pending else {
            throw RedeemDeckRepositoryError.codeUnavailable
        }
        code.markAsSent(at: date)
        try modelContext.save()
        return code.lifecycleStatus
    }

    func restoreSelectionToPending(id: UUID, at date: Date = Date()) throws {
        let codes = try fetchCodes(retrievalID: id)
        guard !codes.isEmpty else { throw RedeemDeckRepositoryError.selectionNotFound }
        for code in codes where code.lifecycleStatus == .sent {
            code.restoreToPending(at: date)
        }
        try modelContext.save()
    }

    @discardableResult
    func restoreCodeToPending(id: UUID, at date: Date = Date()) throws -> CodeLifecycleStatus {
        guard let code = try fetchCode(id: id), code.retrievalID != nil else {
            throw RedeemDeckRepositoryError.codeNotFound
        }
        code.restoreToPending(at: date)
        try modelContext.save()
        return code.lifecycleStatus
    }

    func restoreCodesToPending(
        retrievalID: UUID,
        codeIDs: [UUID],
        at date: Date = Date()
    ) throws {
        let selectedIDs = Set(codeIDs)
        let codes = try fetchCodes(retrievalID: retrievalID)
        guard !codes.isEmpty else { throw RedeemDeckRepositoryError.selectionNotFound }
        for code in codes where selectedIDs.contains(code.id) {
            code.restoreToPending(at: date)
        }
        try modelContext.save()
    }

    @discardableResult
    func releaseSelection(id: UUID) throws -> Int {
        let codes = try fetchCodes(retrievalID: id)
        guard !codes.isEmpty else { throw RedeemDeckRepositoryError.selectionNotFound }
        var releasedCount = 0
        for code in codes where code.lifecycleStatus == .pending {
            code.releasePendingReservation()
            releasedCount += 1
        }
        if releasedCount > 0 { try modelContext.save() }
        return releasedCount
    }

    private func makeSelection(id: UUID, codes: [OfferCode]) throws -> PreparedCodeSelection {
        guard let first = codes.first,
              let app = first.app,
              let category = first.batch?.category else {
            throw RedeemDeckRepositoryError.selectionNotFound
        }
        let prepared = codes.map {
            PreparedCode(
                id: $0.id,
                code: $0.code,
                redemptionURL: $0.redemptionURL,
                status: $0.lifecycleStatus,
                expirationDate: $0.expirationDate
            )
        }
        let createdAt = codes.compactMap { $0.reservedAt ?? $0.sentAt }.min() ?? first.createdAt
        return PreparedCodeSelection(
            id: id,
            appID: app.id,
            appName: app.name,
            appIconURL: app.iconURL,
            appGreeting: app.qrGreeting,
            categoryID: category.id,
            categoryName: category.name,
            productName: category.productName,
            createdAt: createdAt,
            codes: prepared
        )
    }

    private func fetchCategory(id: UUID) throws -> CodeCategory? {
        try modelContext.fetch(FetchDescriptor<CodeCategory>(
            predicate: #Predicate { $0.id == id }
        )).first
    }

    private func fetchCode(id: UUID) throws -> OfferCode? {
        try modelContext.fetch(FetchDescriptor<OfferCode>(
            predicate: #Predicate { $0.id == id }
        )).first
    }

    private func fetchCodes(retrievalID: UUID) throws -> [OfferCode] {
        try modelContext.fetch(FetchDescriptor<OfferCode>(
            predicate: #Predicate { $0.retrievalID == retrievalID },
            sortBy: [SortDescriptor(\.createdAt)]
        ))
    }

    private nonisolated static func shouldSelectBefore(
        _ left: OfferCode,
        _ right: OfferCode
    ) -> Bool {
        switch (left.expirationDate, right.expirationDate) {
        case let (leftDate?, rightDate?):
            if leftDate != rightDate { return leftDate < rightDate }
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            break
        }
        return left.createdAt < right.createdAt
    }
}
