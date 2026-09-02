import SwiftUI

struct ContentView: View {
    let csvImporter: CSVImporter
    let repository: CodeVaultRepository
    let migrationService: CodeVaultMigrationService
    let dashboardRepository: DashboardRepository
    let backupRepository: BackupRepository

    @State private var session = AppSession()
    @State private var feedback = AppFeedbackCenter()
    @State private var startupError: String?

    var body: some View {
        ZStack(alignment: .top) {
            MainView(
                csvImporter: csvImporter,
                repository: repository,
                dashboardRepository: dashboardRepository,
                backupRepository: backupRepository
            )
            .environment(session)
            AppFeedbackOverlay()
        }
        .environment(feedback)
        .task {
            await prepareStore()
        }
        .alert(
            "Data Preparation Failed",
            isPresented: Binding(
                get: { startupError != nil },
                set: { if !$0 { startupError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                startupError = nil
            }
        } message: {
            Text(startupError ?? String(localized: "The local database could not be prepared."))
        }
    }

    private func prepareStore() async {
        do {
            try await migrationService.performAdditiveMigration()
            _ = try await csvImporter.backfillMissingCSVExpirationDates()
            session.dataDidChange()
        } catch {
            startupError = String(localized: "The local database could not be prepared.")
        }
    }
}
