//
//  ContentView.swift
//  AppStoreCodes
//
//  Created by Matteo Comisso on 08/12/2025.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

@MainActor
private func refreshExpirationNotification(for batch: CodeBatch) {
    Task {
        if UserDefaults.standard.bool(forKey: "expirationAlertsEnabled"),
           let snapshot = ExpirationNotificationSnapshot(batch: batch) {
            await ExpirationNotificationService.shared.schedule(snapshot)
        } else {
            await ExpirationNotificationService.shared.cancel(batchID: batch.id)
        }
    }
}

// MARK: - Main Content View

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \AppRecord.name) private var apps: [AppRecord]
    @AppStorage(TrackingSettingsKeys.apiBaseURL) private var trackingAPIBaseURL = ""
    @AppStorage(TrackingSettingsKeys.isEnabled) private var isTrackingEnabled = false

    @State private var selectedApp: AppRecord?
    @State private var selectedBatch: CodeBatch?
    @State private var selectedCodes: Set<OfferCode.ID> = []
    @State private var isImporting = false
    @State private var importResult: CSVImportResult?
    @State private var importError: Error?
    @State private var showingImportAlert = false
    @State private var searchText = ""
    @State private var filterMode: FilterMode = .all
    @State private var sortOrder: SortOrder = .newest
    @State private var isTargeted = false
    @State private var trackingErrorMessage: String?
    @State private var hasTrackingRefreshFailure = false

    #if os(iOS)
    @State private var showingSettings = false
    #endif

    // Edit states
    @State private var editingApp: AppRecord?
    @State private var editingBatch: CodeBatch?
    @State private var showingDeleteConfirmation = false
    @State private var itemToDelete: Any?

    // API fetch states
    @State private var showingFetchSheet = false
    @StateObject private var api = AppStoreConnectAPI.shared

    // Privacy mode
    @State private var isPrivacyModeEnabled = false


    // CSV Import configuration
    @State private var pendingImportURL: URL?
    @State private var csvImportIssueDate = Date()
    @State private var inferredCSVCodeKind: CSVCodeKind = .promo
    @State private var csvCodeKind: CSVCodeKind = .promo
    @State private var csvImportExpirationDate = CSVImportDates.defaultExpirationDate(
        for: Date(),
        codeKind: .promo
    )

    // iOS export
    #if os(iOS)
    @State private var exportDocument = CSVExportDocument(csvContent: "")
    @State private var exportFilename = "Codes.csv"
    @State private var isExportingBatch = false
    @State private var exportError: Error?
    @State private var showingExportAlert = false
    #endif

    enum FilterMode: String, CaseIterable {
        case all = "All"
        case available = "Available"
        case redeemed = "Redeemed"
    }

    enum SortOrder: String, CaseIterable {
        case newest = "Newest"
        case oldest = "Oldest"
        case code = "Code"
    }

    var body: some View {
        NavigationSplitView {
            sidebarView
        } content: {
            codeListView
        } detail: {
            codeDetailView
        }
        .onDrop(of: [UTType.commaSeparatedText, UTType.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .background(Color.accentColor.opacity(0.1))
                    .padding(8)
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [UTType.commaSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    prepareCSVImport(from: url)
                }
            case .failure(let error):
                importError = error
                showingImportAlert = true
            }
        }
        .sheet(item: $pendingImportURL) { url in
            CSVImportConfigSheet(
                url: url,
                issueDate: $csvImportIssueDate,
                inferredCodeKind: inferredCSVCodeKind,
                codeKind: $csvCodeKind,
                expirationDate: $csvImportExpirationDate,
                onImport: { performCSVImport(url: url) },
                onCancel: { pendingImportURL = nil }
            )
        }
        .alert("Import Complete", isPresented: $showingImportAlert) {
            Button("OK") {
                importResult = nil
                importError = nil
            }
        } message: {
            if let result = importResult {
                if result.skippedDuplicates > 0 {
                    Text("Imported \(result.importedCount) codes.\nSkipped \(result.skippedDuplicates) duplicate\(result.skippedDuplicates == 1 ? "" : "s").")
                } else {
                    Text("Imported \(result.importedCount) codes.")
                }
            } else if let error = importError {
                Text(error.localizedDescription)
            }
        }
        #if os(iOS)
        .fileExporter(
            isPresented: $isExportingBatch,
            document: exportDocument,
            contentType: .commaSeparatedText,
            defaultFilename: exportFilename
        ) { result in
            if case .failure(let error) = result {
                exportError = error
                showingExportAlert = true
            }
        }
        .alert("Export Failed", isPresented: $showingExportAlert) {
            Button("OK") {
                exportError = nil
            }
        } message: {
            Text(exportError?.localizedDescription ?? "The batch could not be exported.")
        }
        #endif
        .sheet(item: $editingApp) { app in
            EditAppSheet(app: app)
        }
        .sheet(item: $editingBatch) { batch in
            EditBatchSheet(batch: batch)
        }
        .sheet(isPresented: $showingFetchSheet) {
            FetchFromAPISheet(modelContext: modelContext) { result in
                if let app = apps.first(where: { $0.appStoreId == result.appStoreId }) {
                    selectedApp = app
                }
            }
        }
        #if os(iOS)
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                showingSettings = false
                            }
                        }
                    }
            }
        }
        #endif
        .alert("Tracking Unavailable", isPresented: Binding(
            get: { trackingErrorMessage != nil },
            set: { if !$0 { trackingErrorMessage = nil } }
        )) {
            Button("OK") {
                trackingErrorMessage = nil
            }
        } message: {
            Text(trackingErrorMessage ?? "The tracked link could not be prepared.")
        }
        // Menu bar command handlers
        .onReceive(NotificationCenter.default.publisher(for: .importCSV)) { _ in
            isImporting = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .getNextCode)) { _ in
            if let app = selectedApp {
                getNextAvailableCode(for: app)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .markRedeemed)) { _ in
            markSelectedAsRedeemed()
        }
        .onReceive(NotificationCenter.default.publisher(for: .markAvailable)) { _ in
            markSelectedAsAvailable()
        }
        .onReceive(NotificationCenter.default.publisher(for: .copyCode)) { _ in
            copySelectedCode()
        }
        .onReceive(NotificationCenter.default.publisher(for: .copyURL)) { _ in
            copySelectedURL()
        }
        .task {
            _ = try? CSVImporter(modelContext: modelContext).backfillMissingCSVExpirationDates()
            await reconcileExpirationNotifications()
            await refreshTrackedCodeStatuses()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await refreshTrackedCodeStatuses()
            }
        }
    }

    private func reconcileExpirationNotifications() async {
        let expirationAlertsEnabled = UserDefaults.standard.bool(forKey: "expirationAlertsEnabled")
        guard expirationAlertsEnabled else {
            await ExpirationNotificationService.shared.cancelAll()
            return
        }

        guard let batches = try? modelContext.fetch(FetchDescriptor<CodeBatch>()) else {
            return
        }
        let snapshots = batches.compactMap(ExpirationNotificationSnapshot.init(batch:))
        await ExpirationNotificationService.shared.reconcile(snapshots)
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        List(selection: $selectedApp) {
            Section("Apps") {
                ForEach(apps) { app in
                    AppSidebarRow(
                        app: app,
                        isSelected: selectedApp?.id == app.id && selectedBatch == nil,
                        selectedBatchId: selectedBatch?.id,
                        onSelectApp: {
                            selectedApp = app
                            selectedBatch = nil
                        },
                        onSelectBatch: { batch in
                            selectedApp = app
                            selectedBatch = batch
                        },
                        onEditBatch: { batch in
                            editingBatch = batch
                        },
                        onExportBatch: { batch in
                            exportBatch(batch)
                        },
                        onDeleteBatch: { batch in
                            deleteBatch(batch)
                        },
                        onEditApp: {
                            editingApp = app
                        },
                        onDeleteApp: {
                            deleteApp(app)
                        }
                    )
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 280)
        .toolbar {
            ToolbarItemGroup {
                Button(action: { isImporting = true }) {
                    Label("Import CSV", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("i", modifiers: .command)

                #if os(iOS)
                Button {
                    showingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                #endif

                // TODO: Re-enable when App Store Connect API import is ready
                // if api.isConfigured {
                //     Button(action: { showingFetchSheet = true }) {
                //         Label("Fetch from API", systemImage: "icloud.and.arrow.down")
                //     }
                //     .keyboardShortcut("f", modifiers: [.command, .shift])
                // }
            }
        }
        .overlay {
            if apps.isEmpty {
                ContentUnavailableView {
                    Label("No Apps", systemImage: "app.dashed")
                } description: {
                    Text("Import a CSV file or drag & drop to get started.")
                } actions: {
                    Button("Import CSV") {
                        isImporting = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    // MARK: - Code List

    private var codeListView: some View {
        Group {
            if let app = selectedApp {
                VStack(spacing: 0) {
                    // Toolbar
                    HStack {
                        Picker("Filter", selection: $filterMode) {
                            ForEach(FilterMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 250)

                        Picker("Sort", selection: $sortOrder) {
                            ForEach(SortOrder.allCases, id: \.self) { order in
                                Text(order.rawValue).tag(order)
                            }
                        }
                        .frame(width: 100)

                        Spacer()

                        // Get next available code button
                        Button {
                            getNextAvailableCode(for: app)
                        } label: {
                            Label("Get Next Code", systemImage: "arrow.right.circle")
                        }
                        .disabled(filteredCodes.filter(\.isAvailable).isEmpty)
                        .keyboardShortcut("g", modifiers: .command)

                        // Privacy mode toggle
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isPrivacyModeEnabled.toggle()
                            }
                        } label: {
                            Label(
                                isPrivacyModeEnabled ? "Show Codes" : "Hide Codes",
                                systemImage: isPrivacyModeEnabled ? "eye.slash.fill" : "eye"
                            )
                        }
                        .help(isPrivacyModeEnabled ? "Show codes (Privacy mode)" : "Hide codes (Privacy mode)")
                        .keyboardShortcut("h", modifiers: [.command, .shift])

                        if hasTrackingRefreshFailure {
                            Label("Tracking status may be stale", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }

                        Text("\(filteredCodes.count) codes")
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 80, alignment: .trailing)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                    Divider()

                    codeCollectionView
                }
                .navigationTitle(selectedBatch?.name ?? app.name)
                .platformNavigationSubtitle(selectedBatch != nil ? app.name : "")
                .toolbar {
                    ToolbarItemGroup {
                        if !selectedCodes.isEmpty {
                            Button {
                                markSelectedAsRedeemed()
                            } label: {
                                Label("Mark Redeemed", systemImage: "checkmark.circle")
                            }

                            Button {
                                markSelectedAsAvailable()
                            } label: {
                                Label("Mark Available", systemImage: "circle")
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView("Select an App", systemImage: "app", description: Text("Choose an app from the sidebar to view its codes."))
            }
        }
    }

    @ViewBuilder
    private var codeCollectionView: some View {
        #if os(macOS)
        Table(of: OfferCode.self, selection: $selectedCodes) {
            TableColumn("Status") { code in
                OfferCodeStatusIcon(status: code.displayStatus)
            }
            .width(50)

            TableColumn("Code") { code in
                Text(isPrivacyModeEnabled ? maskedCode(code.code) : code.code)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(code.isExpired && !code.isRedeemed ? .secondary : .primary)
            }
            .width(min: 180, ideal: 200)

            TableColumn("Recipient or Campaign") { code in
                Text(code.assignedTo ?? "—")
                    .foregroundStyle(code.assignedTo == nil ? .secondary : .primary)
            }
            .width(min: 150, ideal: 200)

            TableColumn("Sent") { code in
                if let sentAt = code.sentAt {
                    Text(sentAt, format: .dateTime.month().day())
                        .foregroundStyle(.secondary)
                } else {
                    Text("—")
                        .foregroundStyle(.secondary)
                }
            }
            .width(80)

            TableColumn("Seen") { code in
                if let firstSeenAt = code.firstSeenAt {
                    Text(firstSeenAt, format: .dateTime.month().day())
                        .foregroundStyle(.purple)
                } else {
                    Text("—")
                        .foregroundStyle(.secondary)
                }
            }
            .width(80)

            TableColumn("Batch") { code in
                Text(code.batch?.name ?? "—")
                    .foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 150)

            TableColumn("Expires") { code in
                expirationLabel(for: code)
            }
            .width(80)

            TableColumn("Created") { code in
                Text(code.createdAt, format: .dateTime.month().day())
                    .foregroundStyle(.secondary)
            }
            .width(80)
        } rows: {
            ForEach(filteredCodes) { code in
                TableRow(code)
                    .contextMenu {
                        codeContextMenu(for: code)
                    }
            }
        }
        .searchable(text: $searchText, prompt: "Search codes, recipients, or notes")
        #else
        List(filteredCodes) { code in
            NavigationLink {
                CodeDetailView(code: code, isPrivacyModeEnabled: isPrivacyModeEnabled)
            } label: {
                OfferCodeListRow(
                    code: code,
                    displayCode: isPrivacyModeEnabled ? maskedCode(code.code) : code.code,
                    isSelected: selectedCodes.contains(code.id)
                )
            }
            .simultaneousGesture(TapGesture().onEnded {
                selectedCodes = [code.id]
            })
            .contextMenu {
                codeContextMenu(for: code)
            }
        }
        .listStyle(.plain)
        .searchable(text: $searchText, prompt: "Search codes, recipients, or notes")
        #endif
    }

    @ViewBuilder
    private func expirationLabel(for code: OfferCode) -> some View {
        if let days = code.daysUntilExpiration {
            if days < 0 {
                Text("Expired")
                    .foregroundStyle(.red)
            } else if days == 0 {
                Text("Today")
                    .foregroundStyle(.orange)
            } else if days <= 7 {
                Text("\(days)d")
                    .foregroundStyle(.orange)
            } else if let expirationDate = code.expirationDate {
                Text(expirationDate, format: .dateTime.month().day())
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("—")
                .foregroundStyle(.secondary)
        }
    }

    private var filteredCodes: [OfferCode] {
        guard let app = selectedApp else { return [] }

        var codes: [OfferCode]

        // Filter by batch if selected
        if let batch = selectedBatch {
            codes = batch.codes ?? []
        } else {
            codes = app.codes ?? []
        }

        // Apply status filter
        switch filterMode {
        case .all:
            break
        case .available:
            codes = codes.filter(\.isAvailable)
        case .redeemed:
            codes = codes.filter { $0.isRedeemed }
        }

        // Apply search
        if !searchText.isEmpty {
            codes = codes.filter { code in
                code.code.localizedCaseInsensitiveContains(searchText) ||
                (code.assignedTo?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (code.notes?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        // Apply sort
        switch sortOrder {
        case .newest:
            codes.sort { $0.createdAt > $1.createdAt }
        case .oldest:
            codes.sort { $0.createdAt < $1.createdAt }
        case .code:
            codes.sort { $0.code < $1.code }
        }

        return codes
    }

    @ViewBuilder
    private func codeContextMenu(for code: OfferCode) -> some View {
        Button {
            copyToClipboard(code.code)
        } label: {
            Label("Copy Code", systemImage: "doc.on.doc")
        }

        Button {
            Task {
                await copyDistributionURL(for: code)
            }
        } label: {
            Label("Copy Redemption URL", systemImage: "link")
        }

        Button {
            if let url = URL(string: code.redemptionURL) {
                PlatformURLOpener.open(url)
            }
        } label: {
            Label("Open in Browser", systemImage: "safari")
        }

        Divider()

        if code.sentAt == nil {
            Button {
                code.markAsSent(at: Date())
                if let batch = code.batch {
                    refreshExpirationNotification(for: batch)
                }
            } label: {
                Label("Mark as Sent", systemImage: "paperplane.circle")
            }
        } else {
            Button {
                code.markAsUnsent()
                if let batch = code.batch {
                    refreshExpirationNotification(for: batch)
                }
            } label: {
                Label("Mark as Unsent", systemImage: "paperplane.circle.fill")
            }
        }

        if code.isRedeemed {
            Button {
                code.markAsAvailable()
                if let batch = code.batch {
                    refreshExpirationNotification(for: batch)
                }
            } label: {
                Label("Mark as Available", systemImage: "circle")
            }
        } else {
            Button {
                code.markAsRedeemed()
                if let batch = code.batch {
                    refreshExpirationNotification(for: batch)
                }
            } label: {
                Label("Mark as Redeemed", systemImage: "checkmark.circle")
            }
        }
    }

    // MARK: - Code Detail

    private var codeDetailView: some View {
        Group {
            if selectedCodes.count == 1,
               let codeId = selectedCodes.first,
               let code = filteredCodes.first(where: { $0.id == codeId }) {
                CodeDetailView(code: code, isPrivacyModeEnabled: isPrivacyModeEnabled)
            } else if selectedCodes.count > 1 {
                ContentUnavailableView("\(selectedCodes.count) Codes Selected", systemImage: "square.stack", description: Text("Use the toolbar to perform bulk actions."))
            } else {
                ContentUnavailableView("Select a Code", systemImage: "number", description: Text("Choose a code to view details."))
            }
        }
    }

    // MARK: - Actions

    private func getNextAvailableCode(for app: AppRecord) {
        let availableCodes = (selectedBatch?.codes ?? app.codes ?? []).filter(\.isAvailable)
        guard let nextCode = availableCodes.sorted(by: { $0.createdAt < $1.createdAt }).first else { return }

        // Select the code
        selectedCodes = [nextCode.id]

        if isTrackingEnabled {
            Task {
                await copyDistributionURL(for: nextCode)
            }
        } else {
            copyToClipboard(nextCode.code)
        }
    }

    private func markSelectedAsRedeemed() {
        var affectedBatches: [UUID: CodeBatch] = [:]
        for codeId in selectedCodes {
            if let code = filteredCodes.first(where: { $0.id == codeId }) {
                code.markAsRedeemed()
                if let batch = code.batch {
                    affectedBatches[batch.id] = batch
                }
            }
        }
        affectedBatches.values.forEach(refreshExpirationNotification)
    }

    private func markSelectedAsAvailable() {
        var affectedBatches: [UUID: CodeBatch] = [:]
        for codeId in selectedCodes {
            if let code = filteredCodes.first(where: { $0.id == codeId }) {
                code.markAsAvailable()
                if let batch = code.batch {
                    affectedBatches[batch.id] = batch
                }
            }
        }
        affectedBatches.values.forEach(refreshExpirationNotification)
    }

    private func copyToClipboard(_ string: String) {
        PlatformClipboard.copy(string)
    }

    private func copySelectedCode() {
        guard let codeId = selectedCodes.first,
              let code = filteredCodes.first(where: { $0.id == codeId }) else { return }
        copyToClipboard(code.code)
    }

    private func copySelectedURL() {
        guard let codeId = selectedCodes.first,
              let code = filteredCodes.first(where: { $0.id == codeId }) else { return }
        Task {
            await copyDistributionURL(for: code)
        }
    }

    private func copyDistributionURL(for code: OfferCode) async {
        do {
            let url = try await DistributionCoordinator.shared.effectiveURL(
                for: code,
                trackingEnabled: isTrackingEnabled,
                apiBaseURL: trackingAPIBaseURL,
                apiToken: trackingAPIToken,
                modelContext: modelContext
            )
            copyToClipboard(url.absoluteString)
        } catch {
            trackingErrorMessage = error.localizedDescription
        }
    }

    private var trackingAPIToken: String {
        trackingAPIToken(for: trackingAPIBaseURL)
    }

    private func trackingAPIToken(for apiBaseURL: String) -> String {
        (try? KeychainService.shared.getTrackingAPIToken(forAPIBaseURL: apiBaseURL)) ?? ""
    }

    private func refreshTrackedCodeStatuses() async {
        guard let codes = try? modelContext.fetch(FetchDescriptor<OfferCode>()) else {
            return
        }

        let trackedCodes = codes.filter { $0.trackingLinkID != nil }
        guard !trackedCodes.isEmpty else {
            hasTrackingRefreshFailure = false
            return
        }

        var refreshFailed = false
        let groups = Dictionary(grouping: trackedCodes) {
            $0.trackingAPIBaseURL ?? trackingAPIBaseURL
        }
        for (baseURL, codes) in groups {
            let token = trackingAPIToken(for: baseURL)
            guard !baseURL.isEmpty, !token.isEmpty else {
                refreshFailed = true
                continue
            }
            do {
                try await DistributionCoordinator.shared.refreshStatuses(
                    for: codes,
                    currentAPIBaseURL: baseURL,
                    apiToken: token,
                    modelContext: modelContext
                )
            } catch {
                refreshFailed = true
            }
        }
        hasTrackingRefreshFailure = refreshFailed
    }

    private func maskedCode(_ code: String) -> String {
        // Show first 2 and last 2 characters, mask the rest
        guard code.count > 6 else {
            return String(repeating: "•", count: code.count)
        }
        let prefix = String(code.prefix(2))
        let suffix = String(code.suffix(2))
        let masked = String(repeating: "•", count: code.count - 4)
        return prefix + masked + suffix
    }

    #if os(macOS)
    private func exportBatch(_ batch: CodeBatch) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "\(batch.name).csv"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            try? csvContent(for: batch).write(to: url, atomically: true, encoding: .utf8)
        }
    }
    #else
    private func exportBatch(_ batch: CodeBatch) {
        exportDocument = CSVExportDocument(csvContent: csvContent(for: batch))
        exportFilename = "\(batch.name).csv"
        isExportingBatch = true
    }
    #endif

    private func csvContent(for batch: CodeBatch) -> String {
        (batch.codes ?? [])
            .map { code in
                "\(code.code),\(code.redemptionURL),\(code.isRedeemed ? "redeemed" : "available"),\(code.assignedTo ?? "")"
            }
            .joined(separator: "\n")
    }

    private func deleteBatch(_ batch: CodeBatch) {
        Task {
            await ExpirationNotificationService.shared.cancel(batchID: batch.id)
        }
        if selectedBatch == batch {
            selectedBatch = nil
        }
        modelContext.delete(batch)
    }

    private func deleteApp(_ app: AppRecord) {
        let batchIDs = (app.batches ?? []).map(\.id)
        Task {
            for batchID in batchIDs {
                await ExpirationNotificationService.shared.cancel(batchID: batchID)
            }
        }
        if selectedApp == app {
            selectedApp = nil
            selectedBatch = nil
        }
        modelContext.delete(app)
    }

    // MARK: - Import Handling

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }

                DispatchQueue.main.async {
                    prepareCSVImport(from: url)
                }
            }
            return true
        }
        return false
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            importFromURL(url)
        case .failure(let error):
            self.importError = error
            self.showingImportAlert = true
        }
    }

    private func importFromURL(_ url: URL, expirationDate: Date? = nil) {
        let importer = CSVImporter(modelContext: modelContext)
        do {
            let result = try importer.importCodes(
                from: url,
                expirationDate: expirationDate,
                targetApp: selectedApp
            )
            self.importResult = result
            self.showingImportAlert = true
            scheduleExpirationNotification(for: result)

            // Select the newly imported app and auto-fetch metadata
            if let app = apps.first(where: { $0.appStoreId == result.appStoreId }) {
                selectedApp = app

                // Auto-fetch metadata if not already fetched
                if !app.hasMetadata {
                    Task {
                        try? await AppStoreLookupService.shared.updateAppRecord(app)
                    }
                }
            }
        } catch {
            self.importError = error
            self.showingImportAlert = true
        }
    }

    private func scheduleExpirationNotification(for result: CSVImportResult) {
        guard UserDefaults.standard.bool(forKey: "expirationAlertsEnabled"),
              let batchID = result.batchId else { return }

        let descriptor = FetchDescriptor<CodeBatch>(
            predicate: #Predicate { $0.id == batchID }
        )
        guard let batch = try? modelContext.fetch(descriptor).first,
              batch.id == batchID else { return }

        refreshExpirationNotification(for: batch)
    }

    private func performCSVImport(url: URL) {
        importFromURL(url, expirationDate: csvImportExpirationDate)
        pendingImportURL = nil
    }

    private func prepareCSVImport(from url: URL) {
        let dates = CSVImportDates(url: url)
        csvImportIssueDate = dates.issueDate
        inferredCSVCodeKind = dates.codeKind
        csvCodeKind = dates.codeKind
        csvImportExpirationDate = dates.expirationDate
        pendingImportURL = url
    }
}

private extension View {
    @ViewBuilder
    func platformNavigationSubtitle(_ subtitle: String) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            self.navigationSubtitle(subtitle)
        } else {
            self
        }
        #else
        self.navigationSubtitle(subtitle)
        #endif
    }
}

// MARK: - URL Identifiable Extension

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

struct CSVExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    var csvContent: String

    init(csvContent: String) {
        self.csvContent = csvContent
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let csvContent = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.csvContent = csvContent
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(csvContent.utf8))
    }
}

// MARK: - CSV Import Config Sheet

struct CSVImportConfigSheet: View {
    let url: URL
    @Binding var issueDate: Date
    let inferredCodeKind: CSVCodeKind
    @Binding var codeKind: CSVCodeKind
    @Binding var expirationDate: Date
    let onImport: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Import CSV")
                    .font(.headline)
                Spacer()
                Button("Cancel") { onCancel() }
            }
            .padding()

            Divider()

            Form {
                CSVImportFileSection(url: url)
                CSVImportValiditySection(
                    issueDate: $issueDate,
                    inferredCodeKind: inferredCodeKind,
                    codeKind: $codeKind,
                    expirationDate: $expirationDate
                )
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Import") {
                    onImport()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        #if os(macOS)
        .frame(width: 440, height: 430)
        #endif
    }
}

private struct CSVImportFileSection: View {
    let url: URL

    var body: some View {
        Section("File") {
            LabeledContent("Filename", value: url.lastPathComponent)
        }
    }
}

private struct CSVImportValiditySection: View {
    @Binding var issueDate: Date
    let inferredCodeKind: CSVCodeKind
    @Binding var codeKind: CSVCodeKind
    @Binding var expirationDate: Date

    private var maximumOfferExpirationDate: Date {
        CSVImportDates.defaultExpirationDate(
            for: issueDate,
            codeKind: .offer
        )
    }

    var body: some View {
        Section("Code Validity") {
            Picker("Valid for", selection: $codeKind) {
                Text("4 weeks (Promo code)").tag(CSVCodeKind.promo)
                Text("Up to 6 months (Offer code)").tag(CSVCodeKind.offer)
            }

            LabeledContent("Detected") {
                switch inferredCodeKind {
                case .promo:
                    Text("Promo code")
                case .offer:
                    Text("Offer code")
                }
            }

            DatePicker(
                "Generated on",
                selection: $issueDate,
                displayedComponents: .date
            )

            if codeKind == .promo {
                LabeledContent("Expires on") {
                    Text(expirationDate, format: .dateTime.day().month().year())
                }

                Text("App promo codes expire four weeks after they are generated.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                DatePicker(
                    "Expires on",
                    selection: $expirationDate,
                    in: issueDate...maximumOfferExpirationDate,
                    displayedComponents: .date
                )

                Text("Offer codes can be valid for up to six months. Confirm the expiration date from App Store Connect.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: codeKind) { _, newValue in
            expirationDate = CSVImportDates.defaultExpirationDate(
                for: issueDate,
                codeKind: newValue
            )
        }
        .onChange(of: issueDate) { _, newValue in
            expirationDate = CSVImportDates.defaultExpirationDate(
                for: newValue,
                codeKind: codeKind
            )
        }
    }
}

// MARK: - App Row View

struct AppRowView: View {
    let app: AppRecord

    var body: some View {
        HStack(spacing: 10) {
            // App Icon
            AsyncImage(url: URL(string: app.iconURL ?? "")) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                case .failure, .empty:
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.quaternary)
                        .overlay {
                            Image(systemName: "app")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                @unknown default:
                    EmptyView()
                }
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(app.name)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 12) {
                    Label("\(app.availableCodesCount)", systemImage: "circle")
                        .foregroundStyle(.green)

                    Label("\(app.redeemedCodesCount)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Clipboard Helper

    private func copyToClipboard(_ string: String) {
        PlatformClipboard.copy(string)
    }
}

struct OfferCodeListRow: View {
    let code: OfferCode
    let displayCode: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            OfferCodeStatusIcon(status: code.displayStatus)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayCode)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(code.isExpired && !code.isRedeemed ? .secondary : .primary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(code.assignedTo ?? "Unassigned")
                    if let batchName = code.batch?.name {
                        Text(batchName)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 4) {
                expirationText

                if let firstSeenAt = code.firstSeenAt {
                    Text("Seen \(firstSeenAt, format: .dateTime.month().day())")
                        .font(.caption2)
                        .foregroundStyle(.purple)
                } else if let sentAt = code.sentAt {
                    Text("Sent \(sentAt, format: .dateTime.month().day())")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                } else {
                    Text(code.createdAt, format: .dateTime.month().day())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
    }

    @ViewBuilder
    private var expirationText: some View {
        if let days = code.daysUntilExpiration {
            if days < 0 {
                Text("Expired")
                    .foregroundStyle(.red)
            } else if days == 0 {
                Text("Today")
                    .foregroundStyle(.orange)
            } else if days <= 7 {
                Text("\(days)d")
                    .foregroundStyle(.orange)
            } else if let expirationDate = code.expirationDate {
                Text(expirationDate, format: .dateTime.month().day())
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("—")
                .foregroundStyle(.secondary)
        }
    }
}

private struct OfferCodeStatusIcon: View {
    let status: OfferCodeDisplayStatus

    var body: some View {
        switch status {
        case .redeemed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
        case .expired:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .seen:
            Image(systemName: "eye.circle.fill")
                .foregroundStyle(.purple)
        case .sent:
            Image(systemName: "paperplane.circle.fill")
                .foregroundStyle(.blue)
        case .available:
            Image(systemName: "circle")
                .foregroundStyle(.green)
        }
    }
}

// MARK: - App Sidebar Row

struct AppSidebarRow: View {
    let app: AppRecord
    let isSelected: Bool
    let selectedBatchId: UUID?
    let onSelectApp: () -> Void
    let onSelectBatch: (CodeBatch) -> Void
    let onEditBatch: (CodeBatch) -> Void
    let onExportBatch: (CodeBatch) -> Void
    let onDeleteBatch: (CodeBatch) -> Void
    let onEditApp: () -> Void
    let onDeleteApp: () -> Void

    @State private var isExpanded = {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
        #else
        false
        #endif
    }()

    private var sortedBatches: [CodeBatch] {
        (app.batches ?? []).sorted { $0.importDate > $1.importDate }
    }

    private var hasBatches: Bool {
        !sortedBatches.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    onSelectApp()
                } label: {
                    AppRowView(app: app)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Menu {
                    AppContextMenu(
                        app: app,
                        onEdit: onEditApp,
                        onDelete: onDeleteApp
                    )
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                if hasBatches {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.trailing, 4)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Expandable batch list
            if isExpanded && hasBatches {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(sortedBatches) { batch in
                        Button {
                            onSelectBatch(batch)
                        } label: {
                            HStack {
                                Image(systemName: "folder")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(batch.name)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(batch.totalCodesCount)")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(selectedBatchId == batch.id ? Color.accentColor.opacity(0.15) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("import-\(batch.name)")
                        .contextMenu {
                            Button("Rename Import...") {
                                onEditBatch(batch)
                            }
                            Button("Export Batch...") {
                                onExportBatch(batch)
                            }
                            Divider()
                            Button("Delete Batch", role: .destructive) {
                                onDeleteBatch(batch)
                            }
                        }
                    }
                }
                .padding(.leading, 42)
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - App Context Menu

struct AppContextMenu: View {
    let app: AppRecord
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Group {
            Button("Edit App...") {
                onEdit()
            }

            Divider()

            Menu("Copy") {
                Button("App Name") {
                    copyToClipboard(app.name)
                }

                Button("App Store ID") {
                    copyToClipboard(app.appStoreId)
                }

                if let bundleId = app.bundleId {
                    Button("Bundle ID") {
                        copyToClipboard(bundleId)
                    }
                }

                Button("App Store URL") {
                    copyToClipboard(app.effectiveAppStoreURL)
                }

                if let testFlightURL = app.testFlightURL, !testFlightURL.isEmpty {
                    Button("TestFlight URL") {
                        copyToClipboard(testFlightURL)
                    }
                }

                if let developerName = app.developerName {
                    Button("Developer Name") {
                        copyToClipboard(developerName)
                    }
                }
            }

            Divider()

            if let url = URL(string: app.effectiveAppStoreURL) {
                Button {
                    PlatformURLOpener.open(url)
                } label: {
                    Label("Open in App Store", systemImage: "arrow.up.forward.app")
                }
            }

            if let testFlightURLString = app.testFlightURL,
               !testFlightURLString.isEmpty,
               let url = URL(string: testFlightURLString) {
                Button {
                    PlatformURLOpener.open(url)
                } label: {
                    Label("Open TestFlight", systemImage: "airplane")
                }
            }

            Divider()

            Button("Delete App", role: .destructive) {
                onDelete()
            }
        }
    }

    private func copyToClipboard(_ string: String) {
        PlatformClipboard.copy(string)
    }
}

// MARK: - Code Detail View

struct CodeDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var code: OfferCode
    var isPrivacyModeEnabled: Bool = false
    @AppStorage("shareMessageTemplate") private var shareMessageTemplate = "Here's a promo code for {appName}! Redeem it here: {url}"
    @AppStorage(TrackingSettingsKeys.apiBaseURL) private var trackingAPIBaseURL = ""
    @AppStorage(TrackingSettingsKeys.isEnabled) private var isTrackingEnabled = false
    @State private var isPreparingTrackedLink = false
    @State private var isRefreshingTrackingStatus = false
    @State private var trackingErrorMessage: String?

    private var shareMessage: String {
        ShareMessageHelper.formatMessage(
            template: shareMessageTemplate,
            appName: code.app?.name,
            url: distributionURLString,
            code: code.code
        )
    }

    private var displayCode: String {
        isPrivacyModeEnabled ? maskedCode(code.code) : code.code
    }

    private var displayURL: String {
        isPrivacyModeEnabled ? maskedURL(distributionURLString) : distributionURLString
    }

    private var distributionURLString: String {
        if isTrackingEnabled, let trackedURL = code.trackedURL {
            return trackedURL
        }
        return code.redemptionURL
    }

    private var canDistribute: Bool {
        !isTrackingEnabled || code.trackedURL != nil
    }

    private var sentDate: Binding<Date> {
        Binding(
            get: { code.sentAt ?? Date() },
            set: { code.markAsSent(at: $0) }
        )
    }

    private func maskedCode(_ code: String) -> String {
        guard code.count > 6 else {
            return String(repeating: "•", count: code.count)
        }
        let prefix = String(code.prefix(2))
        let suffix = String(code.suffix(2))
        let masked = String(repeating: "•", count: code.count - 4)
        return prefix + masked + suffix
    }

    private func maskedURL(_ url: String) -> String {
        // Mask the code portion of the URL while keeping the domain visible
        guard let urlObj = URL(string: url),
              let host = urlObj.host else {
            return String(repeating: "•", count: url.count)
        }
        return "https://\(host)/••••••••••••"
    }

    var body: some View {
        Form {
            Section("Code") {
                HStack {
                    Text(displayCode)
                        .font(.system(.title2, design: .monospaced))
                        .textSelection(.enabled)

                    Spacer()

                    Button {
                        PlatformClipboard.copy(code.code)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .help("Copy code")
                    .disabled(isPrivacyModeEnabled)
                    #if os(macOS)
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    #endif
                }

                HStack {
                    Text(displayURL)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)

                    Spacer()

                    Button {
                        Task {
                            if let url = await prepareDistributionURL() {
                                PlatformClipboard.copy(url.absoluteString)
                            }
                        }
                    } label: {
                        if isPreparingTrackedLink {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "doc.on.doc")
                        }
                    }
                    .help("Copy URL")
                    .disabled(isPrivacyModeEnabled || isPreparingTrackedLink)

                    Button {
                        if let url = URL(string: code.redemptionURL) {
                            PlatformURLOpener.open(url)
                        }
                    } label: {
                        Image(systemName: "safari")
                    }
                    .help("Open in browser")

                    ShareLink(item: shareMessage) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .help("Share code")
                    .disabled(isPrivacyModeEnabled || !canDistribute)

                }

                // QR Code displayed directly
                if !isPrivacyModeEnabled {
                    VStack(spacing: 12) {
                        if isTrackingEnabled && !canDistribute {
                            if isPreparingTrackedLink {
                                ProgressView("Preparing tracked link…")
                            } else {
                                Button("Retry Tracked Link") {
                                    Task {
                                        _ = await prepareDistributionURL()
                                    }
                                }
                            }
                        } else if let qrCode = QRCodeGenerator.generate(from: distributionURLString, size: 150) {
                            qrCode
                                .interpolation(.none)
                                .frame(width: 150, height: 150)
                        } else {
                            Text("Could not generate QR code")
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 16) {
                            Text("Scan to redeem")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            ShareLink(item: shareMessage) {
                                Label("Share", systemImage: "square.and.arrow.up")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .disabled(!canDistribute)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }

                if let trackingErrorMessage {
                    Text(trackingErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Status") {
                Toggle("Redeemed", isOn: Binding(
                    get: { code.isRedeemed },
                    set: { newValue in
                        if newValue {
                            code.markAsRedeemed()
                        } else {
                            code.markAsUnredeemed()
                        }
                        if let batch = code.batch {
                            refreshExpirationNotification(for: batch)
                        }
                    }
                ))

                if code.isRedeemed, let date = code.redeemedDate {
                    LabeledContent("Redeemed on") {
                        Text(date, format: .dateTime)
                    }
                }
            }

            Section("Distribution") {
                Toggle("Sent", isOn: Binding(
                    get: { code.sentAt != nil },
                    set: { isSent in
                        if isSent {
                            code.markAsSent(at: Date())
                        } else {
                            code.markAsUnsent()
                        }
                        if let batch = code.batch {
                            refreshExpirationNotification(for: batch)
                        }
                    }
                ))

                if code.sentAt != nil {
                    DatePicker(
                        "Sent on",
                        selection: sentDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                TextField("Recipient or campaign", text: Binding(
                    get: { code.assignedTo ?? "" },
                    set: { code.assignedTo = $0.isEmpty ? nil : $0 }
                ))
            }

            if code.trackingLinkID != nil {
                TrackingStatusSection(
                    firstSeenAt: code.firstSeenAt,
                    lastSeenAt: code.lastSeenAt,
                    visitCount: code.trackingVisitCount,
                    lastSyncedAt: code.trackingLastSyncedAt,
                    isRefreshing: isRefreshingTrackingStatus,
                    onRefresh: {
                        Task {
                            await refreshTrackingStatus()
                        }
                    }
                )
            }

            Section("Distribution notes") {
                TextEditor(text: Binding(
                    get: { code.notes ?? "" },
                    set: { code.notes = $0.isEmpty ? nil : $0 }
                ))
                .frame(minHeight: 80)
            }

            Section("Info") {
                LabeledContent("Created") {
                    Text(code.createdAt, format: .dateTime)
                }

                if let expirationDate = code.expirationDate {
                    LabeledContent("Expires") {
                        Text(expirationDate, format: .dateTime.day().month().year())
                            .foregroundStyle(code.isExpired ? .red : .primary)
                    }
                }

                if let batch = code.batch {
                    LabeledContent("Batch") {
                        Text(batch.name)
                    }
                }

                if let app = code.app {
                    LabeledContent("App Store ID") {
                        Text(app.appStoreId)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Code Details")
        .task(id: "\(code.id.uuidString)-\(isTrackingEnabled)-\(trackingAPIBaseURL)") {
            if isTrackingEnabled {
                _ = await prepareDistributionURL()
            }
            await refreshTrackingStatus()
        }
    }

    private var trackingAPIToken: String {
        let baseURL = code.trackingAPIBaseURL ?? trackingAPIBaseURL
        return (try? KeychainService.shared.getTrackingAPIToken(forAPIBaseURL: baseURL)) ?? ""
    }

    private func prepareDistributionURL() async -> URL? {
        guard !isPreparingTrackedLink else { return nil }
        isPreparingTrackedLink = true
        defer { isPreparingTrackedLink = false }

        do {
            let url = try await DistributionCoordinator.shared.effectiveURL(
                for: code,
                trackingEnabled: isTrackingEnabled,
                apiBaseURL: trackingAPIBaseURL,
                apiToken: trackingAPIToken,
                modelContext: modelContext
            )
            trackingErrorMessage = nil
            return url
        } catch {
            trackingErrorMessage = error.localizedDescription
            return nil
        }
    }

    private func refreshTrackingStatus() async {
        guard code.trackingLinkID != nil, !trackingAPIToken.isEmpty,
              !isRefreshingTrackingStatus else { return }

        isRefreshingTrackingStatus = true
        defer { isRefreshingTrackingStatus = false }

        do {
            try await DistributionCoordinator.shared.refreshStatus(
                for: code,
                apiToken: trackingAPIToken,
                modelContext: modelContext
            )
            trackingErrorMessage = nil
        } catch {
            trackingErrorMessage = error.localizedDescription
        }
    }
}

private struct TrackingStatusSection: View {
    let firstSeenAt: Date?
    let lastSeenAt: Date?
    let visitCount: Int?
    let lastSyncedAt: Date?
    let isRefreshing: Bool
    let onRefresh: () -> Void

    var body: some View {
        Section("Interaction") {
            LabeledContent("Status") {
                if firstSeenAt == nil {
                    Label("Not seen", systemImage: "eye.slash")
                        .foregroundStyle(.secondary)
                } else {
                    Label("Seen", systemImage: "eye.fill")
                        .foregroundStyle(.purple)
                }
            }

            if let firstSeenAt {
                LabeledContent("First seen") {
                    Text(firstSeenAt, format: .dateTime)
                }
            }

            if let lastSeenAt {
                LabeledContent("Last seen") {
                    Text(lastSeenAt, format: .dateTime)
                }
            }

            if let visitCount {
                LabeledContent("Visits", value: visitCount.formatted())
            }

            if let lastSyncedAt {
                LabeledContent("Last refreshed") {
                    Text(lastSyncedAt, format: .relative(presentation: .named))
                }
            }

            Button {
                onRefresh()
            } label: {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Refresh Status", systemImage: "arrow.clockwise")
                }
            }
            .disabled(isRefreshing)

            Text("Seen means the redirect was requested. Link previews and automated scanners can trigger it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Edit App Sheet

struct EditAppSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var app: AppRecord

    @State private var name: String = ""
    @State private var bundleId: String = ""
    @State private var testFlightURL: String = ""
    @State private var testFlightNotes: String = ""
    @State private var notes: String = ""

    @State private var isLoadingMetadata = false
    @State private var metadataError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit App")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()

            Divider()

            ScrollView {
                Form {
                    // App Icon & Basic Info
                    Section {
                        HStack(spacing: 16) {
                            AsyncImage(url: URL(string: app.iconURL ?? "")) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                case .failure:
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(.quaternary)
                                        .overlay {
                                            Image(systemName: "app")
                                                .font(.title)
                                                .foregroundStyle(.secondary)
                                        }
                                case .empty:
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(.quaternary)
                                        .overlay {
                                            if app.iconURL != nil {
                                                ProgressView()
                                            } else {
                                                Image(systemName: "app")
                                                    .font(.title)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                @unknown default:
                                    EmptyView()
                                }
                            }
                            .frame(width: 80, height: 80)

                            VStack(alignment: .leading, spacing: 4) {
                                TextField("App Name", text: $name)
                                    .font(.headline)
                                if let developer = app.developerName {
                                    Text(developer)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                if let genre = app.primaryGenre {
                                    Text(genre)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    // App Store Info (read-only from API)
                    Section("App Store Info") {
                        LabeledContent("App Store ID", value: app.appStoreId)
                        TextField("Bundle ID", text: $bundleId)

                        if let version = app.version {
                            LabeledContent("Version", value: version)
                        }
                        if let price = app.price {
                            LabeledContent("Price", value: price)
                        }

                        HStack {
                            Button {
                                Task { await fetchMetadata() }
                            } label: {
                                HStack {
                                    if isLoadingMetadata {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                    }
                                    Text(app.hasMetadata ? "Refresh Metadata" : "Fetch Metadata")
                                }
                            }
                            .disabled(isLoadingMetadata)

                            if let lastUpdated = app.metadataLastUpdated {
                                Spacer()
                                Text("Updated \(lastUpdated, format: .relative(presentation: .named))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if let error = metadataError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }

                    // TestFlight Info
                    Section("TestFlight") {
                        TextField("TestFlight URL", text: $testFlightURL)
                            .textContentType(.URL)

                        TextField("TestFlight Notes", text: $testFlightNotes, axis: .vertical)
                            .lineLimit(2...4)
                    }

                    // Notes
                    Section("Notes") {
                        TextField("Notes", text: $notes, axis: .vertical)
                            .lineLimit(3...6)
                    }

                    // Links Section
                    Section("Links") {
                        if let url = URL(string: app.effectiveAppStoreURL) {
                            Link(destination: url) {
                                Label("Open in App Store", systemImage: "arrow.up.forward.app")
                            }
                        }

                        if !testFlightURL.isEmpty, let url = URL(string: testFlightURL) {
                            Link(destination: url) {
                                Label("Open TestFlight", systemImage: "airplane")
                            }
                        }
                    }
                }
                .formStyle(.grouped)
            }

            Divider()

            HStack {
                Spacer()
                Button("Save") {
                    saveChanges()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
            }
            .padding()
        }
        #if os(macOS)
        .frame(width: 500, height: 600)
        #endif
        .onAppear {
            loadCurrentValues()
        }
    }

    private func loadCurrentValues() {
        name = app.name
        bundleId = app.bundleId ?? ""
        testFlightURL = app.testFlightURL ?? ""
        testFlightNotes = app.testFlightNotes ?? ""
        notes = app.notes ?? ""
    }

    private func saveChanges() {
        app.name = name
        app.bundleId = bundleId.isEmpty ? nil : bundleId
        app.testFlightURL = testFlightURL.isEmpty ? nil : testFlightURL
        app.testFlightNotes = testFlightNotes.isEmpty ? nil : testFlightNotes
        app.notes = notes.isEmpty ? nil : notes
    }

    private func fetchMetadata() async {
        isLoadingMetadata = true
        metadataError = nil

        do {
            try await AppStoreLookupService.shared.updateAppRecord(app)
            // Reload local state with updated values
            loadCurrentValues()
        } catch {
            metadataError = error.localizedDescription
        }

        isLoadingMetadata = false
    }
}

// MARK: - Edit Batch Sheet

struct EditBatchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var batch: CodeBatch
    @State private var name: String = ""
    @State private var notes: String = ""
    @State private var hasExpirationDate = false
    @State private var expirationDate = Date()
    @FocusState private var isNameFocused: Bool

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Import")
                    .font(.headline)
                Spacer()
            }
            .padding([.horizontal, .top])

            Form {
                Section {
                    TextField("Import Name", text: $name)
                        .focused($isNameFocused)
                        .accessibilityIdentifier("rename-import-name")

                    Text("Use a name that describes the offer, such as “Lifetime” or “3 Months Free”.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                }

                LabeledContent("Imported") {
                    Text(batch.importDate, format: .dateTime)
                }

                Section("Expiration") {
                    Toggle("Track expiration", isOn: $hasExpirationDate)

                    if hasExpirationDate {
                        DatePicker(
                            "Expires on",
                            selection: $expirationDate,
                            displayedComponents: .date
                        )
                    }

                    Text("Changes apply to every code in this import.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Source") {
                    Text(batch.source.rawValue.uppercased())
                }

                LabeledContent("Codes") {
                    Text("\(batch.totalCodesCount) total, \(batch.availableCodesCount) available")
                }
            }
            .formStyle(.grouped)
            .padding()

            Divider()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    saveChanges()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty)
            }
            .padding()
        }
        #if os(macOS)
        .frame(width: 420, height: 430)
        #endif
        .onAppear {
            name = batch.name
            notes = batch.notes ?? ""
            hasExpirationDate = batch.expirationDate != nil
            expirationDate = batch.expirationDate ?? Date()
            isNameFocused = true
        }
    }

    private func saveChanges() {
        batch.name = trimmedName
        batch.notes = notes.isEmpty ? nil : notes
        batch.updateExpirationDate(hasExpirationDate ? expirationDate : nil)

        refreshExpirationNotification(for: batch)
    }
}

// MARK: - Fetch From API Sheet

struct FetchFromAPISheet: View {
    @Environment(\.dismiss) private var dismiss
    let modelContext: ModelContext
    var onComplete: ((CSVImportResult) -> Void)?

    @State private var api = AppStoreConnectAPI.shared
    @State private var apps: [APIApp] = []
    @State private var subscriptionGroups: [APISubscriptionGroup] = []
    @State private var subscriptions: [APISubscription] = []
    @State private var offerCodes: [APISubscriptionOfferCode] = []
    @State private var oneTimeUseCodes: [APIOneTimeUseCode] = []

    @State private var selectedAppId: String?
    @State private var selectedGroupId: String?
    @State private var selectedSubscriptionId: String?
    @State private var selectedOfferCodeId: String?
    @State private var selectedOneTimeUseCodeId: String?

    @State private var isLoading = false
    @State private var error: String?
    @State private var importResult: CSVImportResult?
    @State private var showCreateCodesSheet = false
    @State private var numberOfCodesToCreate = 100
    @State private var expirationDate = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()
    @State private var useExpirationDate = false

    // Pricing and deactivation
    @State private var offerPricing: [OfferCodePricing] = []
    @State private var isLoadingPricing = false
    @State private var showDeactivateConfirmation = false
    @State private var offerToDeactivate: APISubscriptionOfferCode?

    enum FetchStep {
        case selectApp
        case selectGroup
        case selectSubscription
        case selectOffer
        case selectBatch
        case importing
        case complete
    }

    @State private var currentStep: FetchStep = .selectApp

    private var selectedApp: APIApp? {
        apps.first { $0.id == selectedAppId }
    }

    private var selectedGroup: APISubscriptionGroup? {
        subscriptionGroups.first { $0.id == selectedGroupId }
    }

    private var selectedSubscription: APISubscription? {
        subscriptions.first { $0.id == selectedSubscriptionId }
    }

    private var selectedOfferCode: APISubscriptionOfferCode? {
        offerCodes.first { $0.id == selectedOfferCodeId }
    }

    private var selectedOneTimeUseCode: APIOneTimeUseCode? {
        oneTimeUseCodes.first { $0.id == selectedOneTimeUseCodeId }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Fetch Codes from App Store Connect")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()

            Divider()

            Group {
                switch currentStep {
                case .selectApp:
                    appSelectionView
                case .selectGroup:
                    groupSelectionView
                case .selectSubscription:
                    subscriptionSelectionView
                case .selectOffer:
                    offerSelectionView
                case .selectBatch:
                    batchSelectionView
                case .importing:
                    importingView
                case .complete:
                    completeView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        #if os(macOS)
        .frame(width: 500, height: 400)
        #endif
        .task {
            await loadApps()
        }
    }

    private var appSelectionView: some View {
        VStack {
            if isLoading {
                ProgressView("Loading apps...")
            } else if let error = error {
                errorView(error)
            } else if apps.isEmpty {
                Text("No apps found").foregroundStyle(.secondary)
            } else {
                Text("Select an app:")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(apps.enumerated()), id: \.element.id) { _, app in
                            Button {
                                selectedAppId = app.id
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(app.attributes.name).fontWeight(.medium)
                                        Text(app.attributes.bundleId).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selectedAppId == app.id {
                                        Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading)
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button("Next") { Task { await loadSubscriptionGroups() } }
                        .disabled(selectedAppId == nil)
                        .buttonStyle(.borderedProminent)
                }
                .padding()
            }
        }
    }

    private var groupSelectionView: some View {
        VStack {
            if isLoading {
                ProgressView("Loading subscription groups...")
            } else if subscriptionGroups.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
                    Text("No subscription groups found")
                    Text("This app doesn't have any auto-renewable subscriptions.").font(.caption).foregroundStyle(.secondary)
                    Button("Back") { currentStep = .selectApp }
                }
            } else {
                Text("Select a subscription group:").frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(subscriptionGroups.enumerated()), id: \.element.id) { _, group in
                            Button {
                                selectedGroupId = group.id
                            } label: {
                                HStack {
                                    Text(group.attributes.referenceName)
                                    Spacer()
                                    if selectedGroupId == group.id {
                                        Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading)
                        }
                    }
                }

                navButtons(back: { currentStep = .selectApp }, next: { Task { await loadSubscriptions() } }, nextDisabled: selectedGroupId == nil)
            }
        }
    }

    private var subscriptionSelectionView: some View {
        VStack {
            if isLoading {
                ProgressView("Loading subscriptions...")
            } else if subscriptions.isEmpty {
                emptyState("No subscriptions found", back: { currentStep = .selectGroup })
            } else {
                Text("Select a subscription:").frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(subscriptions.enumerated()), id: \.element.id) { _, sub in
                            Button {
                                selectedSubscriptionId = sub.id
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(sub.attributes.name)
                                        Text(sub.attributes.productId).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selectedSubscriptionId == sub.id {
                                        Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading)
                        }
                    }
                }

                navButtons(back: { currentStep = .selectGroup }, next: { Task { await loadOfferCodes() } }, nextDisabled: selectedSubscriptionId == nil)
            }
        }
    }

    private var offerSelectionView: some View {
        VStack {
            if isLoading {
                ProgressView("Loading offer codes...")
            } else if offerCodes.isEmpty {
                emptyState("No active offer codes found", back: { currentStep = .selectSubscription })
            } else {
                Text("Select an offer code:").frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(offerCodes.enumerated()), id: \.element.id) { _, offer in
                            Button {
                                selectedOfferCodeId = offer.id
                                Task { await loadPricingForOffer(offer.id) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(offer.attributes.name).fontWeight(.medium)
                                        Text("\(formatOfferMode(offer.attributes.offerMode)) • \(offer.attributes.numberOfPeriods) period\(offer.attributes.numberOfPeriods == 1 ? "" : "s")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text("Eligibility: \(formatEligibility(offer.attributes.offerEligibility))")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                    Spacer()
                                    if selectedOfferCodeId == offer.id {
                                        Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    offerToDeactivate = offer
                                    showDeactivateConfirmation = true
                                } label: {
                                    Label("Deactivate Offer", systemImage: "xmark.circle")
                                }
                            }
                            Divider().padding(.leading)
                        }
                    }
                }

                // Pricing info for selected offer
                if selectedOfferCodeId != nil {
                    Divider()
                    offerPricingView
                }

                navButtons(back: { currentStep = .selectSubscription }, next: { Task { await loadOneTimeUseCodes() } }, nextDisabled: selectedOfferCodeId == nil)
            }
        }
        .alert("Deactivate Offer Code", isPresented: $showDeactivateConfirmation) {
            Button("Cancel", role: .cancel) {
                offerToDeactivate = nil
            }
            Button("Deactivate", role: .destructive) {
                if let offer = offerToDeactivate {
                    Task { await deactivateOffer(offer) }
                }
            }
        } message: {
            if let offer = offerToDeactivate {
                Text("Are you sure you want to deactivate \"\(offer.attributes.name)\"? This cannot be undone. No new codes can be created or redeemed for this offer.")
            }
        }
    }

    private var offerPricingView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Pricing")
                    .font(.caption)
                    .fontWeight(.medium)
                if isLoadingPricing {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }

            if offerPricing.isEmpty && !isLoadingPricing {
                Text("No pricing data available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // Show first few territories
                let displayPricing = offerPricing.prefix(5)
                HStack(spacing: 8) {
                    ForEach(Array(displayPricing.enumerated()), id: \.offset) { _, price in
                        Text("\(price.territory): \(price.currency) \(price.customerPrice)")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    if offerPricing.count > 5 {
                        Text("+\(offerPricing.count - 5) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func formatOfferMode(_ mode: String) -> String {
        switch mode.lowercased() {
        case "freeoffer": return "Free"
        case "payasyougo": return "Pay As You Go"
        case "payupfront": return "Pay Up Front"
        default: return mode
        }
    }

    private func formatEligibility(_ eligibility: String) -> String {
        switch eligibility.lowercased() {
        case "new": return "New subscribers"
        case "existing": return "Existing subscribers"
        case "expired": return "Expired subscribers"
        case "new_and_existing", "newandexisting": return "New & existing"
        default: return eligibility
        }
    }

    private func loadPricingForOffer(_ offerCodeId: String) async {
        isLoadingPricing = true
        offerPricing = []

        do {
            offerPricing = try await api.fetchOfferCodePricing(offerCodeId: offerCodeId)
        } catch {
            // Silently fail - pricing is optional info
        }

        isLoadingPricing = false
    }

    private func deactivateOffer(_ offer: APISubscriptionOfferCode) async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await api.deactivateOfferCode(offerCodeId: offer.id)
            // Remove from list
            offerCodes.removeAll { $0.id == offer.id }
            if selectedOfferCodeId == offer.id {
                selectedOfferCodeId = nil
                offerPricing = []
            }
        } catch {
            self.error = error.localizedDescription
        }

        offerToDeactivate = nil
    }

    private var batchSelectionView: some View {
        VStack {
            if isLoading {
                ProgressView("Loading code batches...")
            } else if oneTimeUseCodes.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "tray").font(.largeTitle).foregroundStyle(.secondary)
                    Text("No code batches found")
                    Text("Create new codes to get started").font(.caption).foregroundStyle(.secondary)
                    Button("Create New Codes") { showCreateCodesSheet = true }
                        .buttonStyle(.borderedProminent)
                    Button("Back") { currentStep = .selectOffer }
                }
            } else {
                HStack {
                    Text("Select a code batch to import:")
                    Spacer()
                    Button("Create New") { showCreateCodesSheet = true }
                        .buttonStyle(.bordered)
                }
                .padding(.horizontal)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(oneTimeUseCodes.enumerated()), id: \.element.id) { _, batch in
                            Button {
                                selectedOneTimeUseCodeId = batch.id
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text("\(batch.attributes.numberOfCodes) codes")
                                        HStack(spacing: 4) {
                                            Text("Created: \(batch.attributes.createdDate)")
                                            if let expDate = batch.attributes.expirationDate {
                                                Text("•")
                                                Text("Expires: \(expDate)")
                                            }
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if !batch.attributes.active {
                                        Text("Inactive").font(.caption).foregroundStyle(.orange)
                                    }
                                    if selectedOneTimeUseCodeId == batch.id {
                                        Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading)
                        }
                    }
                }

                navButtons(back: { currentStep = .selectOffer }, next: { Task { await importCodes() } }, nextDisabled: selectedOneTimeUseCodeId == nil, nextTitle: "Import")
            }
        }
        .sheet(isPresented: $showCreateCodesSheet) {
            createCodesSheet
        }
    }

    private var createCodesSheet: some View {
        VStack(spacing: 16) {
            Text("Create New Codes")
                .font(.headline)
                .padding(.top)

            Form {
                Section("Number of Codes") {
                    Stepper("\(numberOfCodesToCreate) codes", value: $numberOfCodesToCreate, in: 1...500000, step: numberOfCodesToCreate < 100 ? 10 : (numberOfCodesToCreate < 1000 ? 100 : 1000))

                    HStack {
                        ForEach([25, 100, 500, 1000], id: \.self) { count in
                            Button("\(count)") {
                                numberOfCodesToCreate = count
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                Section("Expiration") {
                    Toggle("Set expiration date", isOn: $useExpirationDate)
                    if useExpirationDate {
                        DatePicker("Expires", selection: $expirationDate, in: Date()..., displayedComponents: .date)
                    }
                }

                if let offer = selectedOfferCode {
                    Section("Offer Details") {
                        LabeledContent("Offer", value: offer.attributes.name)
                        LabeledContent("Mode", value: offer.attributes.offerMode)
                        LabeledContent("Periods", value: "\(offer.attributes.numberOfPeriods)")
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") {
                    showCreateCodesSheet = false
                }
                Spacer()
                Button("Create Codes") {
                    Task { await createCodes() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading)
            }
            .padding()
        }
        #if os(macOS)
        .frame(width: 400, height: 400)
        #endif
    }

    private func createCodes() async {
        guard let offerCodeId = selectedOfferCodeId else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let newBatch = try await api.createOneTimeUseCodes(
                offerCodeId: offerCodeId,
                numberOfCodes: numberOfCodesToCreate,
                expirationDate: useExpirationDate ? expirationDate : nil
            )

            // Add to list and auto-select
            oneTimeUseCodes.insert(newBatch, at: 0)
            selectedOneTimeUseCodeId = newBatch.id
            showCreateCodesSheet = false
        } catch {
            self.error = error.localizedDescription
        }
    }

    private var importingView: some View {
        VStack(spacing: 16) {
            ProgressView().scaleEffect(1.5)
            Text("Importing codes...")
            Text("This may take a moment").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var completeView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundStyle(.green)
            if let result = importResult {
                Text("Import Complete!").font(.headline)
                Text("Imported \(result.importedCount) codes")
                if result.skippedDuplicates > 0 {
                    Text("Skipped \(result.skippedDuplicates) duplicates").foregroundStyle(.secondary)
                }
            }
            Button("Done") {
                if let result = importResult { onComplete?(result) }
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.red)
            Text(message).multilineTextAlignment(.center)
            Button("Retry") { Task { await loadApps() } }
        }
        .padding()
    }

    private func emptyState(_ message: String, back: @escaping () -> Void) -> some View {
        VStack(spacing: 16) {
            Text(message).foregroundStyle(.secondary)
            Button("Back") { back() }
        }
    }

    private func navButtons(back: @escaping () -> Void, next: @escaping () -> Void, nextDisabled: Bool, nextTitle: String = "Next") -> some View {
        HStack {
            Button("Back") { back() }
            Spacer()
            Button(nextTitle) { next() }.disabled(nextDisabled).buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func loadApps() async {
        isLoading = true
        error = nil
        do { apps = try await api.fetchApps() }
        catch { self.error = error.localizedDescription }
        isLoading = false
    }

    private func loadSubscriptionGroups() async {
        guard let app = selectedApp else { return }
        isLoading = true
        do {
            subscriptionGroups = try await api.fetchSubscriptionGroups(appId: app.id)
            currentStep = .selectGroup
        } catch { self.error = error.localizedDescription }
        isLoading = false
    }

    private func loadSubscriptions() async {
        guard let group = selectedGroup else { return }
        isLoading = true
        do {
            subscriptions = try await api.fetchSubscriptions(groupId: group.id)
            currentStep = .selectSubscription
        } catch { self.error = error.localizedDescription }
        isLoading = false
    }

    private func loadOfferCodes() async {
        guard let subscription = selectedSubscription else { return }
        isLoading = true
        do {
            offerCodes = try await api.fetchOfferCodes(subscriptionId: subscription.id)
            currentStep = .selectOffer
        } catch { self.error = error.localizedDescription }
        isLoading = false
    }

    private func loadOneTimeUseCodes() async {
        guard let offerCode = selectedOfferCode else { return }
        isLoading = true
        do {
            oneTimeUseCodes = try await api.fetchOneTimeUseCodes(offerCodeId: offerCode.id)
            currentStep = .selectBatch
        } catch { self.error = error.localizedDescription }
        isLoading = false
    }

    private func importCodes() async {
        guard let app = selectedApp, let offer = selectedOfferCode, let batch = selectedOneTimeUseCode else { return }
        currentStep = .importing
        isLoading = true
        do {
            let csvContent = try await api.fetchCodeValues(oneTimeUseCodeId: batch.id)

            // Parse expiration date from API response
            var expirationDate: Date? = nil
            if let expirationString = batch.attributes.expirationDate {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withFullDate]
                expirationDate = formatter.date(from: expirationString)
            }

            let result = try importCodesFromCSV(csvContent, appName: app.attributes.name, appId: app.id, batchName: offer.attributes.name, expirationDate: expirationDate)
            self.importResult = result
            currentStep = .complete
        } catch {
            self.error = error.localizedDescription
            currentStep = .selectBatch
        }
        isLoading = false
    }

    private func importCodesFromCSV(_ content: String, appName: String, appId: String, batchName: String, expirationDate: Date? = nil) throws -> CSVImportResult {
        let descriptor = FetchDescriptor<AppRecord>(predicate: #Predicate { $0.appStoreId == appId })
        let appRecord: AppRecord
        let isNewApp: Bool
        if let existing = try? modelContext.fetch(descriptor).first {
            appRecord = existing
            isNewApp = false
            if appRecord.name != appName { appRecord.name = appName }
        } else {
            appRecord = AppRecord(name: appName, appStoreId: appId)
            modelContext.insert(appRecord)
            isNewApp = true
        }

        let result = try CSVImporter(modelContext: modelContext).importCodes(
            fromCSVString: content,
            batchName: batchName,
            source: .api,
            expirationDate: expirationDate,
            targetApp: appRecord
        )

        if let batchID = result.batchId {
            let batchDescriptor = FetchDescriptor<CodeBatch>(
                predicate: #Predicate { $0.id == batchID }
            )
            if let batch = try? modelContext.fetch(batchDescriptor).first {
                refreshExpirationNotification(for: batch)
            }
        }

        // Auto-fetch metadata for new apps
        if isNewApp || !appRecord.hasMetadata {
            Task {
                try? await AppStoreLookupService.shared.updateAppRecord(appRecord)
            }
        }

        return result
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [AppRecord.self, CodeBatch.self, OfferCode.self], inMemory: true)
}
