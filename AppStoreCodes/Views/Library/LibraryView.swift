import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    let csvImporter: CSVImporter
    let repository: CodeVaultRepository
    let dashboardRepository: DashboardRepository
    let onManage: (AppSummary) -> Void
    let onRequestCodes: (AppSummary, UUID?) -> Void

    @Environment(AppSession.self) var session
    @Environment(AppFeedbackCenter.self) var feedback
    @Query(sort: \AppRecord.name) private var allApps: [AppRecord]
    @AppStorage("librarySortOrder") private var sortOrder = LibrarySortOrder.name
    @State var isShowingAddApp = false
    @State var editingApp: AppRecord?
    @State var archiveCandidate: AppRecord?
    @State var isShowingFileImporter = false
    @State var pendingImport: ImportDraft?
    @State var isInspecting = false
    @State var didRefreshArtwork = false
    @State var errorMessage: String?
    @State var inventoryByApp: [UUID: AppInventorySummary] = [:]
    @State var pendingSelections: [PreparedCodeSelection] = []

    var apps: [AppRecord] {
        allApps.filter { !$0.isArchived }.sorted { left, right in
            switch sortOrder {
            case .name:
                left.name.localizedStandardCompare(right.name) == .orderedAscending
            case .available:
                (inventoryByApp[left.id]?.availableCount ?? 0)
                    > (inventoryByApp[right.id]?.availableCount ?? 0)
            case .expiring:
                (inventoryByApp[left.id]?.expiringCount ?? 0)
                    > (inventoryByApp[right.id]?.expiringCount ?? 0)
            }
        }
    }

    var body: some View {
        List {
            if !pendingRetrievals.isEmpty {
                Section("Continue Retrieval") {
                    ForEach(pendingRetrievals) { item in
                        NavigationLink(
                            value: LibraryRoute.retrieval(
                                .resume(app: item.app, selectionID: item.selection.id)
                            )
                        ) {
                            PendingRetrievalRow(item: item)
                                .contentShape(.rect)
                        }
                    }
                }
                Section("Apps") { appRows }
            } else {
                appRows
            }
        }
        .navigationTitle("Codes")
        .codeVaultScrollEdgeStyle()
        .task(id: session.dataRevision) {
            await loadDashboard()
            await refreshMissingArtwork()
        }
        .refreshable { await loadDashboard() }
        .overlay { emptyState }
        .toolbar { addMenu }
        .toolbarTitleMenu {
            ForEach(LibrarySortOrder.allCases) { option in
                Button {
                    sortOrder = option
                } label: {
                    HStack {
                        Text(option.localizedName)
                        Spacer()
                        Image(systemName: "checkmark")
                            .opacity(sortOrder == option ? 1 : 0)
                    }
                }
                .accessibilityAddTraits(sortOrder == option ? .isSelected : [])
            }
        }
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false,
            onCompletion: handleFileSelection
        )
        .sheet(isPresented: $isShowingAddApp) {
            AppEditorSheet(onSave: showAppSaved)
                .codeVaultFormPresentation()
        }
        .sheet(item: $editingApp) { app in
            AppEditorSheet(app: app, onSave: showAppSaved)
                .codeVaultFormPresentation()
        }
        .sheet(item: $pendingImport) { draft in
            ImportConfigurationSheet(
                draft: draft,
                csvImporter: csvImporter,
                onComplete: finishImport
            )
            .codeVaultFormPresentation()
        }
        .alert(
            "Archive this app?",
            isPresented: archiveConfirmation
        ) {
            Button("Archive App", role: .destructive, action: archiveSelectedApp)
            Button("Cancel", role: .cancel) { archiveCandidate = nil }
        } message: {
            Text("Its code categories, batches, and codes will be kept and can be restored later.")
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

    @ViewBuilder
    private var appRows: some View {
        ForEach(apps) { app in
            appButton(app, summary: appSummary(for: app))
        }
    }

    private func appButton(_ app: AppRecord, summary: AppSummary) -> some View {
        Button {
            onRequestCodes(summary, nil)
        } label: {
            LibraryAppRow(app: summary, inventory: inventoryByApp[app.id])
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button("Get", systemImage: "paperplane") {
                onRequestCodes(summary, nil)
            }
            .disabled(inventoryByApp[app.id]?.availableCount == 0)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Manage", systemImage: "slider.horizontal.3") {
                onManage(summary)
            }
            Button("Archive", systemImage: "archivebox", role: .destructive) {
                archiveCandidate = app
            }
            Button("Edit", systemImage: "pencil") { editingApp = app }
        }
        .contextMenu {
            Button("Get Codes", systemImage: "paperplane") {
                onRequestCodes(summary, nil)
            }
            .disabled(inventoryByApp[app.id]?.availableCount == 0)
            Button("Manage Codes", systemImage: "slider.horizontal.3") {
                onManage(summary)
            }
            Button("Edit App", systemImage: "pencil") { editingApp = app }
            Divider()
            Button("Archive App", systemImage: "archivebox", role: .destructive) {
                archiveCandidate = app
            }
        }
    }

    private var pendingRetrievals: [PendingRetrievalPresentation] {
        pendingSelections.compactMap { selection in
            guard let record = allApps.first(where: { $0.id == selection.appID }) else {
                return nil
            }
            return PendingRetrievalPresentation(
                selection: selection,
                app: appSummary(for: record)
            )
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if allApps.filter({ !$0.isArchived }).isEmpty && !isInspecting {
            ContentUnavailableView {
                Label("No Codes", systemImage: "ticket")
            } description: {
                Text("Use the Add menu to import codes or add an App.")
            }
        } else if isInspecting {
            ProgressView("Inspecting File")
        }
    }

    @ToolbarContentBuilder
    private var addMenu: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Import Code File", systemImage: "square.and.arrow.down", action: showFileImporter)
                Button("Add App", systemImage: "plus", action: showAddApp)
            } label: {
                Label("Add", systemImage: "plus")
            }
        }
    }

    private var archiveConfirmation: Binding<Bool> {
        Binding(
            get: { archiveCandidate != nil },
            set: { if !$0 { archiveCandidate = nil } }
        )
    }

    private func appSummary(for app: AppRecord) -> AppSummary {
        AppSummary(
            id: app.id,
            name: app.name,
            appStoreID: app.appStoreId,
            iconURL: app.iconURL,
            appStoreURL: app.appStoreURL,
            qrGreeting: app.qrGreeting
        )
    }

}
