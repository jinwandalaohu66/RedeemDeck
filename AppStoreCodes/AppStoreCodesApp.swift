import SwiftData
import SwiftUI

private func makeSharedModelContainer() -> ModelContainer {
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
    let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    #if DEBUG
    let isRunningUITests = ProcessInfo.processInfo.arguments.contains("--ui-testing")
    #else
    let isRunningUITests = false
    #endif
    let configuration = ModelConfiguration(
        schema: schema,
        isStoredInMemoryOnly: isRunningTests || isRunningUITests
    )

    do {
        let container = try ModelContainer(for: schema, configurations: [configuration])
        #if DEBUG
        if isRunningUITests {
            try seedUITestData(
                in: container,
                includesPosterDeck: ProcessInfo.processInfo.arguments.contains(
                    "--ui-testing-poster-deck"
                )
            )
        }
        #endif
        return container
    } catch {
        fatalError("Could not create local model container: \(error)")
    }
}

#if DEBUG
@MainActor
private func seedUITestData(
    in container: ModelContainer,
    includesPosterDeck: Bool
) throws {
    let app = AppRecord(name: "UI Test App", appStoreId: "123456789")
    let category = CodeCategory(
        name: "Launch Offer",
        productName: "UI Test Product",
        app: app
    )
    let batch = CodeBatch(name: "Launch Codes", source: .csv)
    batch.app = app
    batch.category = category
    batch.codeKind = .appPromo
    let code = OfferCode(
        code: "TESTCODE123",
        redemptionURL: "https://apps.apple.com/redeem?id=123456789&code=TESTCODE123"
    )
    code.app = app
    code.batch = batch
    container.mainContext.insert(app)
    container.mainContext.insert(category)
    container.mainContext.insert(batch)
    container.mainContext.insert(code)
    if includesPosterDeck {
        for index in 1...2 {
            let extraCode = OfferCode(
                code: "TESTCODE12\(index)",
                redemptionURL: "https://apps.apple.com/redeem?id=123456789&code=TESTCODE12\(index)"
            )
            extraCode.app = app
            extraCode.batch = batch
            container.mainContext.insert(extraCode)
        }
    }
    try container.mainContext.save()
}
#endif

@main
struct AppStoreCodesApp: App {
    private let sharedModelContainer: ModelContainer
    private let csvImporter: CSVImporter
    private let repository: CodeVaultRepository
    private let migrationService: CodeVaultMigrationService
    private let dashboardRepository: DashboardRepository
    private let backupRepository: BackupRepository

    init() {
        let container = makeSharedModelContainer()
        sharedModelContainer = container
        csvImporter = CSVImporter(modelContainer: container)
        repository = CodeVaultRepository(modelContainer: container)
        migrationService = CodeVaultMigrationService(modelContainer: container)
        dashboardRepository = DashboardRepository(modelContainer: container)
        backupRepository = BackupRepository(modelContainer: container)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                csvImporter: csvImporter,
                repository: repository,
                migrationService: migrationService,
                dashboardRepository: dashboardRepository,
                backupRepository: backupRepository
            )
        }
        .modelContainer(sharedModelContainer)
    }
}
