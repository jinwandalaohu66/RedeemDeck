//
//  ContentView.swift
//  AppStoreCodes
//
//  Created by Matteo Comisso on 08/12/2025.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Main Content View

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AppRecord.name) private var apps: [AppRecord]

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
    @State private var csvImportExpirationDate = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()
    @State private var csvImportUseExpiration = true

    // iOS export
    #if os(iOS)
    @State private var exportingBatch: CodeBatch?
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
                    pendingImportURL = url
                }
            case .failure(let error):
                importError = error
                showingImportAlert = true
            }
        }
        .sheet(item: $pendingImportURL) { url in
            CSVImportConfigSheet(
                url: url,
                expirationDate: $csvImportExpirationDate,
                useExpiration: $csvImportUseExpiration,
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
                Text("Imported \(result.importedCount) codes.\nSkipped \(result.skippedDuplicates) duplicates.")
            } else if let error = importError {
                Text(error.localizedDescription)
            }
        }
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
                        }
                    )
                    .contextMenu {
                        AppContextMenu(
                            app: app,
                            onEdit: { editingApp = app },
                            onDelete: { deleteApp(app) }
                        )
                    }
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

                if api.isConfigured {
                    Button(action: { showingFetchSheet = true }) {
                        Label("Fetch from API", systemImage: "icloud.and.arrow.down")
                    }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                }
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
                        .disabled(filteredCodes.filter { !$0.isRedeemed }.isEmpty)
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

                        Text("\(filteredCodes.count) codes")
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 80, alignment: .trailing)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                    Divider()

                    // Code table
                    Table(of: OfferCode.self, selection: $selectedCodes) {
                        TableColumn("Status") { code in
                            if code.isRedeemed {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.orange)
                            } else if code.isExpired {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundStyle(.green)
                            }
                        }
                        .width(50)

                        TableColumn("Code") { code in
                            Text(isPrivacyModeEnabled ? maskedCode(code.code) : code.code)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(code.isExpired && !code.isRedeemed ? .secondary : .primary)
                        }
                        .width(min: 180, ideal: 200)

                        TableColumn("Assigned To") { code in
                            Text(code.assignedTo ?? "—")
                                .foregroundStyle(code.assignedTo == nil ? .secondary : .primary)
                        }
                        .width(min: 150, ideal: 200)

                        TableColumn("Batch") { code in
                            Text(code.batch?.name ?? "—")
                                .foregroundStyle(.secondary)
                        }
                        .width(min: 100, ideal: 150)

                        TableColumn("Expires") { code in
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
                                } else {
                                    Text(code.expirationDate!, format: .dateTime.month().day())
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Text("—")
                                    .foregroundStyle(.secondary)
                            }
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
                    .searchable(text: $searchText, prompt: "Search codes or users")
                }
                .navigationTitle(selectedBatch?.name ?? app.name)
                .navigationSubtitle(selectedBatch != nil ? app.name : "")
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
            codes = codes.filter { !$0.isRedeemed }
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
            copyToClipboard(code.redemptionURL)
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

        if code.isRedeemed {
            Button {
                code.markAsAvailable()
            } label: {
                Label("Mark as Available", systemImage: "circle")
            }
        } else {
            Button {
                code.markAsRedeemed()
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
        let availableCodes = (selectedBatch?.codes ?? app.codes ?? []).filter { !$0.isRedeemed }
        guard let nextCode = availableCodes.sorted(by: { $0.createdAt < $1.createdAt }).first else { return }

        // Copy to clipboard
        copyToClipboard(nextCode.code)

        // Select the code
        selectedCodes = [nextCode.id]
    }

    private func markSelectedAsRedeemed() {
        for codeId in selectedCodes {
            if let code = filteredCodes.first(where: { $0.id == codeId }) {
                code.markAsRedeemed()
            }
        }
    }

    private func markSelectedAsAvailable() {
        for codeId in selectedCodes {
            if let code = filteredCodes.first(where: { $0.id == codeId }) {
                code.markAsAvailable()
            }
        }
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
        copyToClipboard(code.redemptionURL)
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

            var csvContent = ""
            for code in batch.codes ?? [] {
                csvContent += "\(code.code),\(code.redemptionURL),\(code.isRedeemed ? "redeemed" : "available"),\(code.assignedTo ?? "")\n"
            }

            try? csvContent.write(to: url, atomically: true, encoding: .utf8)
        }
    }
    #else
    private func exportBatch(_ batch: CodeBatch) {
        // On iOS, we'll use the share sheet via exportingBatch state
        exportingBatch = batch
    }
    #endif

    private func deleteBatch(_ batch: CodeBatch) {
        modelContext.delete(batch)
    }

    private func deleteApp(_ app: AppRecord) {
        if selectedApp == app {
            selectedApp = nil
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
                    importFromURL(url)
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
            let result = try importer.importCodes(from: url, expirationDate: expirationDate)
            self.importResult = result
            self.showingImportAlert = true

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

    private func performCSVImport(url: URL) {
        let expiration = csvImportUseExpiration ? csvImportExpirationDate : nil
        importFromURL(url, expirationDate: expiration)
        pendingImportURL = nil
    }
}

// MARK: - URL Identifiable Extension

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

// MARK: - CSV Import Config Sheet

struct CSVImportConfigSheet: View {
    let url: URL
    @Binding var expirationDate: Date
    @Binding var useExpiration: Bool
    let onImport: () -> Void
    let onCancel: () -> Void

    private let maxExpirationDate = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()

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
                Section("File") {
                    LabeledContent("Filename", value: url.lastPathComponent)
                }

                Section("Expiration Date") {
                    Toggle("Set expiration date for codes", isOn: $useExpiration)

                    if useExpiration {
                        DatePicker(
                            "Expires on",
                            selection: $expirationDate,
                            in: Date()...maxExpirationDate,
                            displayedComponents: .date
                        )

                        Text("Maximum expiration: 6 months from today")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            ForEach([1, 3, 6], id: \.self) { months in
                                Button("\(months) mo") {
                                    expirationDate = Calendar.current.date(byAdding: .month, value: months, to: Date()) ?? Date()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
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
        .frame(width: 400, height: 350)
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
                        .foregroundStyle(.orange)
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

    @State private var isExpanded = false

    private var sortedBatches: [CodeBatch] {
        (app.batches ?? []).sorted { $0.importDate > $1.importDate }
    }

    private var hasBatches: Bool {
        !sortedBatches.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main app row - tappable to select
            Button {
                onSelectApp()
            } label: {
                HStack(spacing: 8) {
                    AppRowView(app: app)

                    Spacer()

                    // Expand/collapse chevron for batches
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
                        .contextMenu {
                            Button("Rename Batch...") {
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
    @Bindable var code: OfferCode
    var isPrivacyModeEnabled: Bool = false

    private var displayCode: String {
        isPrivacyModeEnabled ? maskedCode(code.code) : code.code
    }

    private var displayURL: String {
        isPrivacyModeEnabled ? maskedURL(code.redemptionURL) : code.redemptionURL
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
                        PlatformClipboard.copy(code.redemptionURL)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .help("Copy URL")
                    .disabled(isPrivacyModeEnabled)

                    Button {
                        if let url = URL(string: code.redemptionURL) {
                            PlatformURLOpener.open(url)
                        }
                    } label: {
                        Image(systemName: "safari")
                    }
                    .help("Open in browser")
                }
            }

            Section("Status") {
                Toggle("Redeemed", isOn: Binding(
                    get: { code.isRedeemed },
                    set: { newValue in
                        if newValue {
                            code.markAsRedeemed()
                        } else {
                            code.markAsAvailable()
                        }
                    }
                ))

                if code.isRedeemed, let date = code.redeemedDate {
                    LabeledContent("Redeemed on") {
                        Text(date, format: .dateTime)
                    }
                }
            }

            Section("Assignment") {
                TextField("Email or user", text: Binding(
                    get: { code.assignedTo ?? "" },
                    set: { code.assignedTo = $0.isEmpty ? nil : $0 }
                ))
            }

            Section("Notes") {
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
        .frame(width: 500, height: 600)
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

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Batch Name", text: $name)

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                }

                LabeledContent("Imported") {
                    Text(batch.importDate, format: .dateTime)
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
                    batch.name = name
                    batch.notes = notes.isEmpty ? nil : notes
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty)
            }
            .padding()
        }
        .frame(width: 400, height: 350)
        .onAppear {
            name = batch.name
            notes = batch.notes ?? ""
        }
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
        .frame(width: 500, height: 400)
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
        .frame(width: 400, height: 400)
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
        let lines = content.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

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

        let codeBatch = CodeBatch(name: batchName, source: .api, expirationDate: expirationDate)
        codeBatch.app = appRecord
        modelContext.insert(codeBatch)

        let existingCodes = Set((appRecord.codes ?? []).map { $0.code })
        var importedCount = 0
        var skippedDuplicates = 0

        for line in lines {
            let components = line.components(separatedBy: ",")
            guard components.count >= 2 else { continue }
            let code = components[0].trimmingCharacters(in: .whitespaces)
            let url = components[1].trimmingCharacters(in: .whitespaces)

            if existingCodes.contains(code) { skippedDuplicates += 1; continue }

            let offerCode = OfferCode(code: code, redemptionURL: url, expirationDate: expirationDate)
            offerCode.app = appRecord
            offerCode.batch = codeBatch
            modelContext.insert(offerCode)
            importedCount += 1
        }

        try modelContext.save()

        // Auto-fetch metadata for new apps
        if isNewApp || !appRecord.hasMetadata {
            Task {
                try? await AppStoreLookupService.shared.updateAppRecord(appRecord)
            }
        }

        return CSVImportResult(importedCount: importedCount, skippedDuplicates: skippedDuplicates, appStoreId: appId, batchId: codeBatch.id)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [AppRecord.self, CodeBatch.self, OfferCode.self], inMemory: true)
}
