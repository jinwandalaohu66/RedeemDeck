import SwiftUI

struct SettingsRootView: View {
    let repository: CodeVaultRepository
    let backupRepository: BackupRepository
    let dashboardRepository: DashboardRepository

    @Environment(AppFeedbackCenter.self) private var feedback
    @AppStorage("expirationAlertsEnabled") private var expirationAlertsEnabled = false
    @State private var notificationError: String?

    var body: some View {
        List {
            Section("Reminders") {
                Toggle("Expiration Alerts", isOn: $expirationAlertsEnabled)
                    .onChange(of: expirationAlertsEnabled, handleNotificationChange)
            }

            Section("Data") {
                NavigationLink("Backup and Restore") {
                    BackupRestoreView(repository: backupRepository)
                }
                NavigationLink("Archived Items") {
                    ArchivedItemsView(repository: repository)
                }
                LabeledContent("Storage", value: String(localized: "On This Device"))
            }
        }
        .navigationTitle("Settings")
        .alert(
            "Notifications Unavailable",
            isPresented: Binding(
                get: { notificationError != nil },
                set: { if !$0 { notificationError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { notificationError = nil }
        } message: {
            Text(notificationError ?? String(localized: "Notification permission was not granted."))
        }
    }

    private func handleNotificationChange(_ oldValue: Bool, _ newValue: Bool) {
        Task {
            if newValue {
                let granted = await ExpirationNotificationService.shared.requestAuthorization()
                guard granted else {
                    expirationAlertsEnabled = false
                    notificationError = String(localized: "Notification permission was not granted.")
                    return
                }
                do {
                    let snapshots = try await dashboardRepository
                        .loadExpirationNotificationSnapshots()
                    await ExpirationNotificationService.shared.reconcile(snapshots)
                    feedback.show(String(localized: "Expiration alerts enabled."))
                } catch {
                    expirationAlertsEnabled = false
                    notificationError = String(
                        localized: "Expiration reminders could not be prepared."
                    )
                }
            } else {
                await ExpirationNotificationService.shared.cancelAll()
                feedback.show(String(localized: "Expiration alerts disabled."), tone: .information)
            }
        }
    }
}
