import SwiftUI

struct CodeCategoryListView: View {
    let app: AppSummary
    let categories: [CodeCategorySummary]
    let retrievalHistory: [RetrievalHistorySummary]
    let repository: RedeemDeckRepository
    let reload: () async -> Void

    @Environment(AppSession.self) private var session
    @Environment(AppFeedbackCenter.self) private var feedback
    @State private var isShowingAdd = false
    @State private var editingCategory: CodeCategorySummary?
    @State private var archiveCandidate: CodeCategorySummary?
    @State private var errorMessage: String?

    private var products: [String] {
        Array(Set(categories.map(\.productName))).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    var body: some View {
        List {
            if !retrievalHistory.isEmpty {
                Section("Recent Retrievals") {
                    ForEach(retrievalHistory) { item in
                        NavigationLink(
                            value: LibraryRoute.retrieval(
                                .resume(app: app, selectionID: item.id)
                            )
                        ) {
                            RetrievalHistoryRow(item: item)
                                .contentShape(.rect)
                        }
                    }
                }
            }
            ForEach(products, id: \.self) { product in
                Section(product) {
                    ForEach(categories.filter { $0.productName == product }) { category in
                        categoryLink(category)
                    }
                }
            }
        }
        .navigationTitle(app.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .redeemDeckScrollEdgeStyle()
        .overlay { emptyState }
        .toolbar { toolbarContent }
        .refreshable { await reload() }
        .sheet(isPresented: $isShowingAdd) { categoryEditor() }
        .sheet(item: $editingCategory) { categoryEditor($0) }
        .alert(
            "Archive this code category?",
            isPresented: Binding(
                get: { archiveCandidate != nil },
                set: { if !$0 { archiveCandidate = nil } }
            )
        ) {
            Button("Archive Code Category", role: .destructive, action: archive)
            Button("Cancel", role: .cancel) { archiveCandidate = nil }
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

    private func categoryLink(_ category: CodeCategorySummary) -> some View {
        NavigationLink(value: LibraryRoute.category(app, category)) {
            CodeCategoryRow(category: category)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Archive Code Category", systemImage: "archivebox", role: .destructive) {
                archiveCandidate = category
            }
            Button("Edit Code Category", systemImage: "pencil") {
                editingCategory = category
            }
        }
        .contextMenu {
            Button("Edit Code Category", systemImage: "pencil") {
                editingCategory = category
            }
            Button("Archive Code Category", systemImage: "archivebox", role: .destructive) {
                archiveCandidate = category
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if categories.isEmpty {
            ContentUnavailableView {
                Label("No Code Categories", systemImage: "rectangle.stack")
            } description: {
                Text("Add a subscription or offer before importing its codes.")
            } actions: {
                Button("Add Code Category", action: { isShowingAdd = true })
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Add Code Category", systemImage: "plus") { isShowingAdd = true }
                if let url = URL(string: app.effectiveAppStoreURL) {
                    Link("View in App Store", destination: url)
                }
            } label: {
                Label("More", systemImage: "ellipsis")
            }
        }
    }

    private func categoryEditor(_ category: CodeCategorySummary? = nil) -> some View {
        CodeCategoryEditorSheet(
            app: app,
            category: category,
            repository: repository
        ) {
            session.dataDidChange()
            feedback.show(String(localized: "Code category saved."))
        }
        .redeemDeckFormPresentation()
    }

    private func archive() {
        guard let category = archiveCandidate else { return }
        archiveCandidate = nil
        Task {
            do {
                try await repository.setArchived(.category(category.id), archived: true)
                session.dataDidChange()
                feedback.show(String(localized: "Code category archived."))
            } catch {
                errorMessage = UserFacingError.message(for: error)
            }
        }
    }
}

private struct RetrievalHistoryRow: View {
    let item: RetrievalHistorySummary

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(item.categoryName)
                    .lineLimit(1)
                Text(item.createdAt, format: .dateTime.month().day().hour().minute())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(status)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var status: String {
        if item.pendingCount > 0 {
            return String(localized: "\(item.pendingCount) pending")
        }
        if item.sentCount > 0 {
            return String(localized: "\(item.sentCount) sent")
        }
        return String(localized: "\(item.expiredCount) expired")
    }
}
