import SwiftUI

struct CodeCategoryBrowserView: View {
    let app: AppSummary
    let category: CodeCategorySummary
    let repository: CodeVaultRepository
    let dashboardRepository: DashboardRepository

    @Environment(AppSession.self) private var session
    @Environment(AppFeedbackCenter.self) private var feedback
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var filter = CodeBrowserFilter.all
    @State private var pageSize = 200
    @State private var snapshot = CodeCategoryCodeSnapshot.empty
    @State private var loadedRequest: CodeCategoryCodeLoadRequest?
    @State private var isLoading = false
    @State private var isShowingEdit = false
    @State private var isShowingAdd = false
    @State private var isConfirmingArchive = false
    @State private var errorMessage: String?

    init(
        app: AppSummary,
        category: CodeCategorySummary,
        repository: CodeVaultRepository,
        dashboardRepository: DashboardRepository
    ) {
        self.app = app
        self.category = category
        self.repository = repository
        self.dashboardRepository = dashboardRepository
    }

    private var loadRequest: CodeCategoryCodeLoadRequest {
        CodeCategoryCodeLoadRequest(
            revision: session.dataRevision,
            searchText: searchText,
            filter: filter,
            limit: pageSize
        )
    }

    var body: some View {
        List {
            Section {
                if snapshot.rows.isEmpty, !isLoading {
                    Text("No codes match this filter.")
                        .foregroundStyle(.secondary)
                }
                ForEach(snapshot.rows) { code in
                    codeLink(code)
                }
                if snapshot.rows.count < snapshot.matchingCount {
                    Button("Load More") { pageSize += 200 }
                        .disabled(isLoading)
                }
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } header: {
                HStack(spacing: 10) {
                    AppArtworkView(iconURL: app.iconURL, size: 28)
                    Text(category.name)
                    Spacer()
                    Text("\(snapshot.availableCount)/\(snapshot.totalCount)")
                        .monospacedDigit()
                }
            }
        }
        .navigationTitle(app.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .codeVaultScrollEdgeStyle()
        .searchable(text: $searchText, prompt: "Search Codes")
        .toolbar { toolbarContent }
        .task(id: loadRequest) { await loadCodes(request: loadRequest) }
        .onChange(of: searchText) { _, _ in pageSize = 200 }
        .onChange(of: filter) { _, _ in pageSize = 200 }
        .sheet(isPresented: $isShowingEdit) { categoryEditor(category) }
        .sheet(isPresented: $isShowingAdd) { categoryEditor() }
        .alert(
            "Archive this code category?",
            isPresented: $isConfirmingArchive
        ) {
            Button("Archive Code Category", role: .destructive, action: archive)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its batches and codes will be kept and can be restored later.")
        }
        .alert(
            "Unable to Complete Action",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? String(localized: "The operation could not be completed. Please try again."))
        }
    }

    private func codeLink(_ code: CodeRowSummary) -> some View {
        NavigationLink(value: LibraryRoute.code(app, category, code)) {
            CodeListRow(code: code)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button("Copy Code", systemImage: "doc.on.doc") { copy(code) }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            statusAction(for: code)
        }
    }

    @ViewBuilder
    private func statusAction(for code: CodeRowSummary) -> some View {
        switch code.status {
        case .available:
            Button("Mark as Sent", systemImage: "paperplane") {
                update(code, action: .sent)
            }
        case .pending:
            Button("Mark as Sent", systemImage: "paperplane") {
                update(code, action: .sent)
            }
            Button("Make Available Again", systemImage: "arrow.uturn.backward") {
                update(code, action: .available)
            }
        case .sent:
            Button("Make Available Again", systemImage: "arrow.uturn.backward") {
                update(code, action: .available)
            }
        case .expired:
            EmptyView()
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                ForEach(CodeBrowserFilter.allCases) { option in
                    Button {
                        filter = option
                    } label: {
                        HStack {
                            Text(option.localizedName)
                            Spacer()
                            Image(systemName: "checkmark")
                                .opacity(filter == option ? 1 : 0)
                        }
                    }
                    .accessibilityAddTraits(filter == option ? .isSelected : [])
                }
            } label: {
                Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
            }
            Menu {
                Button("Edit Code Category") { isShowingEdit = true }
                Button("Add Code Category") { isShowingAdd = true }
                if let url = URL(string: app.effectiveAppStoreURL) {
                    Link("View in App Store", destination: url)
                }
                Divider()
                Button("Archive Code Category", role: .destructive) {
                    isConfirmingArchive = true
                }
            } label: {
                Label("More", systemImage: "ellipsis")
            }
        }
    }

    private func categoryEditor(_ value: CodeCategorySummary? = nil) -> some View {
        CodeCategoryEditorSheet(
            app: app,
            category: value,
            repository: repository
        ) {
            session.dataDidChange()
            feedback.show(String(localized: "Code category saved."))
        }
        .codeVaultFormPresentation()
    }

    private func loadCodes(request: CodeCategoryCodeLoadRequest) async {
        guard loadedRequest != request else { return }
        if !request.searchText.isEmpty {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let updatedSnapshot = try await dashboardRepository.loadCategoryCodes(
                categoryID: category.id,
                searchText: request.searchText,
                filter: request.filter,
                limit: request.limit
            )
            guard !Task.isCancelled else { return }
            snapshot = updatedSnapshot
            loadedRequest = request
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = UserFacingError.message(for: error)
        }
    }

    private func copy(_ code: CodeRowSummary) {
        CodeCopyAction.perform(
            codeID: code.id,
            value: code.code,
            status: code.status,
            repository: repository,
            session: session,
            feedback: feedback
        )
    }

    private func update(_ code: CodeRowSummary, action: CodeStatusAction) {
        Task {
            do {
                try await repository.updateCodeStatus(id: code.id, action: action)
                session.dataDidChange()
                feedback.show(String(localized: "Code status updated."))
            } catch {
                errorMessage = UserFacingError.message(for: error)
            }
        }
    }

    private func archive() {
        Task {
            do {
                try await repository.setArchived(.category(category.id), archived: true)
                session.dataDidChange()
                feedback.show(String(localized: "Code category archived."))
                dismiss()
            } catch {
                errorMessage = UserFacingError.message(for: error)
            }
        }
    }
}
