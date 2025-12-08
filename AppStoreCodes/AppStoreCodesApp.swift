//
//  AppStoreCodesApp.swift
//  AppStoreCodes
//
//  Created by Matteo Comisso on 08/12/2025.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

@main
struct AppStoreCodesApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            AppRecord.self,
            CodeBatch.self,
            OfferCode.self,
        ])

        // Configure for iCloud sync
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private("iCloud.com.mcsoftware.AppStoreCodes")
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        #if os(macOS)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Import CSV...") {
                    NotificationCenter.default.post(name: .importCSV, object: nil)
                }
                .keyboardShortcut("i", modifiers: .command)
            }

            CommandMenu("Codes") {
                Button("Get Next Available Code") {
                    NotificationCenter.default.post(name: .getNextCode, object: nil)
                }
                .keyboardShortcut("g", modifiers: .command)

                Divider()

                Button("Mark Selected as Redeemed") {
                    NotificationCenter.default.post(name: .markRedeemed, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button("Mark Selected as Available") {
                    NotificationCenter.default.post(name: .markAvailable, object: nil)
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])

                Divider()

                Button("Copy Selected Code") {
                    NotificationCenter.default.post(name: .copyCode, object: nil)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Button("Copy Redemption URL") {
                    NotificationCenter.default.post(name: .copyURL, object: nil)
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])
            }
        }
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let importCSV = Notification.Name("importCSV")
    static let getNextCode = Notification.Name("getNextCode")
    static let markRedeemed = Notification.Name("markRedeemed")
    static let markAvailable = Notification.Name("markAvailable")
    static let copyCode = Notification.Name("copyCode")
    static let copyURL = Notification.Name("copyURL")
}

// MARK: - Settings View

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            APISettingsView()
                .tabItem {
                    Label("App Store Connect", systemImage: "key")
                }
        }
        .frame(width: 500, height: 400)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("autoMarkRedeemed") private var autoMarkRedeemed = false
    @AppStorage("copyURLInsteadOfCode") private var copyURLInsteadOfCode = false

    var body: some View {
        Form {
            Section {
                Toggle("Auto-mark as redeemed when copying", isOn: $autoMarkRedeemed)
                Toggle("Copy redemption URL instead of code", isOn: $copyURLInsteadOfCode)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct APISettingsView: View {
    @AppStorage("apiKeyId") private var apiKeyId = ""
    @State private var issuerId: String = ""
    @State private var apiKeyFile: String = "No file selected"
    @State private var isValidating = false
    @State private var validationResult: ValidationResult?
    @State private var hasKey = false
    @State private var showingFilePicker = false

    enum ValidationResult {
        case success
        case failure(String)
    }

    var body: some View {
        Form {
            Section("App Store Connect API Credentials") {
                TextField("Key ID", text: $apiKeyId)
                    #if os(macOS)
                    .textFieldStyle(.roundedBorder)
                    #endif

                TextField("Issuer ID", text: $issuerId)
                    #if os(macOS)
                    .textFieldStyle(.roundedBorder)
                    #endif

                HStack {
                    Text("API Key (.p8)")
                    Spacer()
                    if hasKey {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Configured")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(apiKeyFile)
                            .foregroundStyle(.secondary)
                    }
                    Button("Choose...") {
                        showingFilePicker = true
                    }
                }
            }

            Section {
                HStack {
                    Button("Validate Credentials") {
                        Task { await validateCredentials() }
                    }
                    .disabled(apiKeyId.isEmpty || issuerId.isEmpty || !hasKey || isValidating)

                    if isValidating {
                        ProgressView()
                            .scaleEffect(0.7)
                    }

                    Spacer()

                    if let result = validationResult {
                        switch result {
                        case .success:
                            Label("Valid", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        case .failure(let message):
                            Label(message, systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                                .lineLimit(1)
                        }
                    }
                }

                if hasKey {
                    Button("Remove API Key", role: .destructive) {
                        removeAPIKey()
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("How to get API credentials:")
                        .font(.headline)

                    Text("1. Go to App Store Connect → Users and Access → Integrations")
                    Text("2. Click the + button to create a new key")
                    Text("3. Give it a name and select 'Admin' access")
                    Text("4. Download the .p8 file (only available once!)")
                    Text("5. Copy the Key ID and Issuer ID shown on the page")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        #if os(macOS)
        .padding()
        #endif
        .onAppear {
            loadCredentials()
        }
        .onChange(of: apiKeyId) { _, _ in
            saveCredentials()
        }
        .onChange(of: issuerId) { _, _ in
            saveCredentials()
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [UTType(filenameExtension: "p8") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
    }

    private func loadCredentials() {
        hasKey = !apiKeyId.isEmpty && KeychainService.shared.hasAPIKey(keyId: apiKeyId)

        if let storedIssuerId = try? KeychainService.shared.getIssuerId() {
            issuerId = storedIssuerId
        }

        if hasKey {
            apiKeyFile = "AuthKey_\(apiKeyId).p8"
        }
    }

    private func saveCredentials() {
        if !issuerId.isEmpty {
            try? KeychainService.shared.saveIssuerId(issuerId)
        }
        AppStoreConnectAPI.shared.checkConfiguration()
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            // Start accessing security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                validationResult = .failure("Cannot access file")
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let keyData = try Data(contentsOf: url)

                if apiKeyId.isEmpty {
                    // Try to extract key ID from filename (AuthKey_XXXXXXXXXX.p8)
                    let filename = url.deletingPathExtension().lastPathComponent
                    if filename.hasPrefix("AuthKey_") {
                        apiKeyId = String(filename.dropFirst(8))
                    }
                }

                guard !apiKeyId.isEmpty else {
                    validationResult = .failure("Please enter Key ID first")
                    return
                }

                try KeychainService.shared.saveAPIKey(keyData, keyId: apiKeyId)
                apiKeyFile = url.lastPathComponent
                hasKey = true
                validationResult = nil
                AppStoreConnectAPI.shared.checkConfiguration()
            } catch {
                validationResult = .failure("Failed to save key: \(error.localizedDescription)")
            }

        case .failure(let error):
            validationResult = .failure(error.localizedDescription)
        }
    }

    private func removeAPIKey() {
        guard !apiKeyId.isEmpty else { return }
        try? KeychainService.shared.deleteAPIKey(keyId: apiKeyId)
        hasKey = false
        apiKeyFile = "No file selected"
        validationResult = nil
        AppStoreConnectAPI.shared.checkConfiguration()
    }

    private func validateCredentials() async {
        isValidating = true
        validationResult = nil

        do {
            _ = try await AppStoreConnectAPI.shared.validateCredentials()
            validationResult = .success
        } catch {
            validationResult = .failure(error.localizedDescription)
        }

        isValidating = false
    }
}
