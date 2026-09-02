import SwiftUI

struct AppCodeManagementView: View {
    let app: AppSummary
    let repository: CodeVaultRepository
    let dashboardRepository: DashboardRepository

    @Environment(AppSession.self) private var session
    @State private var categories: [CodeCategorySummary] = []
    @State private var history: [RetrievalHistorySummary] = []
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        Group {
            if isLoading && categories.isEmpty {
                ProgressView("Loading Code Management")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError, categories.isEmpty {
                ContentUnavailableView {
                    Label("Unable to Load Codes", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            } else {
                CodeCategoryListView(
                    app: app,
                    categories: categories,
                    retrievalHistory: history,
                    repository: repository,
                    reload: load
                )
            }
        }
        .task(id: session.dataRevision) { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let categoriesRequest = dashboardRepository.loadCodeCategories(appID: app.id)
            async let historyRequest = dashboardRepository.loadRetrievalHistory(appID: app.id)
            let (loadedCategories, loadedHistory) = try await (
                categoriesRequest,
                historyRequest
            )
            guard !Task.isCancelled else { return }
            categories = loadedCategories
            history = loadedHistory
            loadError = nil
        } catch {
            guard !Task.isCancelled else { return }
            loadError = UserFacingError.message(for: error)
        }
    }
}
