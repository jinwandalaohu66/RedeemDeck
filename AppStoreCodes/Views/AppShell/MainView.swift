import SwiftUI

struct MainView: View {
    let csvImporter: CSVImporter
    let repository: CodeVaultRepository
    let dashboardRepository: DashboardRepository
    let backupRepository: BackupRepository

    @State private var isShowingSettings = false
    @State private var path: [LibraryRoute] = []
    @State private var quantityPrompt: CodeQuantityPrompt?
    @State private var quantityText = "1"
    @State private var isPreparingPrompt = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack(path: $path) {
            LibraryView(
                csvImporter: csvImporter,
                repository: repository,
                dashboardRepository: dashboardRepository,
                onManage: { path.append(.manage($0)) },
                onRequestCodes: prepareQuantityPrompt
            )
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button("Settings", systemImage: "gearshape") {
                        isShowingSettings = true
                    }
                }
            }
            .navigationDestination(for: LibraryRoute.self, destination: destination)
        }
        .disabled(isPreparingPrompt)
        .overlay {
            if isPreparingPrompt {
                ProgressView("Preparing Codes")
            }
        }
        .alert(
            "Get Codes",
            isPresented: quantityPromptPresented,
            presenting: quantityPrompt,
            actions: quantityActions,
            message: quantityMessage
        )
        .alert(
            "Unable to Get Codes",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? String(localized: "The operation could not be completed. Please try again."))
        }
        .sheet(isPresented: $isShowingSettings) {
            NavigationStack {
                SettingsRootView(
                    repository: repository,
                    backupRepository: backupRepository,
                    dashboardRepository: dashboardRepository
                )
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { isShowingSettings = false }
                    }
                }
            }
            .appFeedbackPresenter()
            .codeVaultFormPresentation()
        }
    }

    @ViewBuilder
    private func destination(_ route: LibraryRoute) -> some View {
        switch route {
        case .manage(let app):
            AppCodeManagementView(
                app: app,
                repository: repository,
                dashboardRepository: dashboardRepository
            )
        case .category(let app, let category):
            CodeCategoryBrowserView(
                app: app,
                category: category,
                repository: repository,
                dashboardRepository: dashboardRepository
            )
        case .code(let app, let category, let code):
            CodeDetailView(
                code: code,
                app: app,
                categoryName: category.name,
                productName: category.productName,
                repository: repository
            )
        case .retrieval(let request):
            CodeRetrievalView(request: request, repository: repository)
        }
    }

    @ViewBuilder
    private func quantityActions(_ prompt: CodeQuantityPrompt) -> some View {
        TextField("Quantity", text: $quantityText)
            #if os(iOS)
            .keyboardType(.numberPad)
            #endif

        if prompt.categories.count == 1, let category = prompt.categories.first {
            Button("Get") {
                openRetrieval(app: prompt.app, category: category)
            }
        } else {
            ForEach(prompt.categories) { category in
                Button("\(category.name) · \(category.availableCount) available") {
                    openRetrieval(app: prompt.app, category: category)
                }
            }
        }
        Button("Cancel", role: .cancel) { quantityPrompt = nil }
    }

    private func quantityMessage(_ prompt: CodeQuantityPrompt) -> some View {
        Text(
            prompt.categories.count == 1
                ? String(localized: "Choose how many codes to retrieve from \(prompt.app.name).")
                : String(localized: "Enter a quantity, then choose a code type for \(prompt.app.name).")
        )
    }

    private var quantityPromptPresented: Binding<Bool> {
        Binding(
            get: { quantityPrompt != nil },
            set: { if !$0 { quantityPrompt = nil } }
        )
    }

    private var requestedQuantity: Int? {
        Int(quantityText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func prepareQuantityPrompt(app: AppSummary, categoryID: UUID?) {
        guard !isPreparingPrompt else { return }
        isPreparingPrompt = true
        Task {
            defer { isPreparingPrompt = false }
            do {
                let loaded = try await dashboardRepository.loadCodeCategories(appID: app.id)
                let categories = categoryID.map { id in loaded.filter { $0.id == id } } ?? loaded
                guard categories.contains(where: { $0.availableCount > 0 }) else {
                    throw CodeVaultRepositoryError.noAvailableCode
                }
                quantityText = "1"
                quantityPrompt = CodeQuantityPrompt(
                    app: app,
                    categories: categories.filter { $0.availableCount > 0 }
                )
            } catch {
                errorMessage = UserFacingError.message(for: error)
            }
        }
    }

    private func openRetrieval(app: AppSummary, category: CodeCategorySummary) {
        guard let quantity = requestedQuantity, quantity > 0 else {
            showQuantityError(String(localized: "Enter a valid quantity."))
            return
        }
        guard quantity <= category.availableCount else {
            showQuantityError(String(localized: "Only \(category.availableCount) codes are currently available."))
            return
        }
        quantityPrompt = nil
        path.append(.retrieval(.new(app: app, categoryID: category.id, quantity: quantity)))
    }

    private func showQuantityError(_ message: String) {
        quantityPrompt = nil
        Task {
            await Task.yield()
            errorMessage = message
        }
    }
}
