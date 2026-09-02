import SwiftData
@testable import RedeemDeck

@MainActor
enum TestModelStore {
    static func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            AppRecord.self,
            CodeCategory.self,
            CodeBatch.self,
            OfferCode.self,
            Campaign.self,
            Recipient.self,
            DistributionRecord.self,
            ActivityEvent.self,
            MessageTemplate.self,
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
