import Foundation
import Testing
@testable import CodeVault

struct OfferCodeLifecycleTests {
    @Test @MainActor
    func availableCodeMovesThroughPendingAndSent() {
        let code = OfferCode(code: "FLOW1", redemptionURL: "https://example.com")
        let retrievalID = UUID()
        let reservedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let sentAt = Date(timeIntervalSince1970: 1_800_000_000)

        #expect(code.isAvailable)
        #expect(code.lifecycleStatus == .available)

        code.reserve(for: retrievalID, at: reservedAt)
        #expect(!code.isAvailable)
        #expect(code.lifecycleStatus == .pending)
        #expect(code.retrievalID == retrievalID)

        code.markAsSent(at: sentAt, assignedTo: "Taylor", notes: "Launch")

        #expect(!code.isAvailable)
        #expect(code.lifecycleStatus == .sent)
        #expect(code.sentAt == sentAt)
        #expect(code.reservedAt == nil)
    }

    @Test @MainActor
    func makingCodeAvailableClearsCurrentAndRetiredState() {
        let code = OfferCode(code: "RESET1", redemptionURL: "https://example.com")
        code.markAsSent()
        code.isRedeemed = true
        code.redeemedDate = Date()
        code.redemptionCount = 1
        code.revokedAt = Date()

        code.markAsAvailable()

        #expect(code.isAvailable)
        #expect(code.lifecycleStatus == .available)
        #expect(code.sentAt == nil)
        #expect(code.redeemedDate == nil)
        #expect(code.redemptionCount == 0)
        #expect(code.revokedAt == nil)
    }

    @Test @MainActor
    func expirationTakesPrecedenceOverDeliveryState() {
        let code = OfferCode(
            code: "EXPIRED1",
            redemptionURL: "https://example.com",
            expirationDate: .distantPast
        )
        code.markAsSent()

        #expect(code.lifecycleStatus == .expired)
        #expect(!code.isAvailable)
    }

    @Test @MainActor
    func retiredLifecycleFieldsNormalizeWithoutLosingMeaning() {
        let redeemed = OfferCode(code: "OLD1", redemptionURL: "https://example.com")
        let redeemedAt = Date(timeIntervalSince1970: 1_700_000_000)
        redeemed.isRedeemed = true
        redeemed.redeemedDate = redeemedAt
        redeemed.redemptionCount = 1

        redeemed.normalizeRetiredLifecycle()

        #expect(redeemed.lifecycleStatus == .sent)
        #expect(redeemed.sentAt == redeemedAt)
        #expect(!redeemed.isRedeemed)
        #expect(redeemed.redeemedDate == nil)
        #expect(redeemed.redemptionCount == 0)

        let revoked = OfferCode(code: "OLD2", redemptionURL: "https://example.com")
        let revokedAt = Date(timeIntervalSince1970: 1_710_000_000)
        revoked.revokedAt = revokedAt

        revoked.normalizeRetiredLifecycle()

        #expect(revoked.archivedAt == revokedAt)
        #expect(revoked.revokedAt == nil)
    }
}
