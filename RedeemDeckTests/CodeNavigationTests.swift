import Foundation
import Testing
@testable import RedeemDeck

struct CodeNavigationTests {
    @Test
    func rowIdentityRemainsStableWhenItsDisplayStateChanges() {
        let id = UUID()
        let available = CodeRowSummary(
            id: id,
            code: "CODE1",
            redemptionURL: "https://example.com/CODE1",
            status: .available,
            expirationDate: nil,
            notes: nil
        )
        let sent = CodeRowSummary(
            id: id,
            code: "CODE1",
            redemptionURL: "https://example.com/CODE1",
            status: .sent,
            expirationDate: .distantFuture,
            notes: "Sent for launch"
        )

        #expect(available == sent)
        #expect(Set([available, sent]).count == 1)
    }
}
