//
//  TrackingSettingsView.swift
//  CodeVault
//

import SwiftUI

/// Settings for an optional, self-hosted interaction tracking backend.
///
/// This view is platform-independent so iOS can present it from its own
/// settings route while macOS embeds it in the app's Settings scene.
struct TrackingSettingsView: View {
    @AppStorage(TrackingSettingsKeys.apiBaseURL) private var apiBaseURL = ""
    @AppStorage(TrackingSettingsKeys.isEnabled) private var isTrackingEnabled = false

    @State private var apiToken = ""
    @State private var hasStoredToken = false
    @State private var isTestingConnection = false
    @State private var status: TrackingSettingsStatus?

    private var normalizedBaseURL: URL? {
        Self.validBaseURL(from: apiBaseURL)
    }

    private var canEnableTracking: Bool {
        normalizedBaseURL != nil && hasStoredToken
    }

    var body: some View {
        Form {
            TrackingEndpointSection(
                apiBaseURL: $apiBaseURL,
                apiToken: $apiToken,
                hasStoredToken: hasStoredToken,
                isTestingConnection: isTestingConnection,
                canTestConnection: normalizedBaseURL != nil && !apiToken.isEmpty,
                status: status,
                saveToken: saveToken,
                removeToken: removeToken,
                testConnection: {
                    Task { await testConnection() }
                }
            )

            TrackingInteractionSection(
                isTrackingEnabled: $isTrackingEnabled,
                canEnableTracking: canEnableTracking
            )

            TrackingPrivacySection()
        }
        .formStyle(.grouped)
        .navigationTitle("Tracking")
        #if os(macOS)
        .padding()
        #endif
        .task {
            loadTokenForCurrentDomain()
        }
        .onChange(of: apiBaseURL) { _, _ in
            status = nil
            loadTokenForCurrentDomain()
        }
        .onChange(of: apiToken) { _, _ in
            status = nil
        }
    }

    private static func validBaseURL(from value: String) -> URL? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmedValue),
              components.scheme?.lowercased() == "https",
              components.host?.isEmpty == false,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              components.path.isEmpty || components.path == "/",
              let url = components.url else {
            return nil
        }
        return url
    }

    private func loadTokenForCurrentDomain() {
        guard let normalizedBaseURL else {
            apiToken = ""
            hasStoredToken = false
            disableTrackingIfConfigurationIsIncomplete()
            return
        }

        do {
            apiToken = try KeychainService.shared.getTrackingAPIToken(
                forAPIBaseURL: normalizedBaseURL.absoluteString
            )
            hasStoredToken = true
        } catch KeychainError.itemNotFound {
            apiToken = ""
            hasStoredToken = false
            disableTrackingIfConfigurationIsIncomplete()
        } catch {
            apiToken = ""
            hasStoredToken = false
            status = .failure("The API token could not be read from Keychain.")
            disableTrackingIfConfigurationIsIncomplete()
        }
    }

    private func saveToken() {
        let trimmedToken = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty, let normalizedBaseURL else {
            status = .failure("Enter a valid HTTPS API domain.")
            return
        }

        do {
            try KeychainService.shared.saveTrackingAPIToken(
                trimmedToken,
                forAPIBaseURL: normalizedBaseURL.absoluteString
            )
            apiBaseURL = normalizedBaseURL.absoluteString
            apiToken = trimmedToken
            hasStoredToken = true
            status = .saved
        } catch {
            hasStoredToken = false
            status = .failure("The API token could not be saved to Keychain.")
            disableTrackingIfConfigurationIsIncomplete()
        }
    }

    private func removeToken() {
        guard let normalizedBaseURL else { return }
        do {
            try KeychainService.shared.deleteTrackingAPIToken(
                forAPIBaseURL: normalizedBaseURL.absoluteString
            )
            apiToken = ""
            hasStoredToken = false
            isTrackingEnabled = false
            status = .removed
        } catch {
            status = .failure("The API token could not be removed from Keychain.")
        }
    }

    private func testConnection() async {
        guard let baseURL = normalizedBaseURL else {
            status = .failure("Enter a valid HTTPS API domain.")
            return
        }

        let trimmedToken = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            status = .failure("Enter an API token.")
            return
        }

        isTestingConnection = true
        status = nil
        defer { isTestingConnection = false }

        do {
            let configuration = try TrackingConfiguration(
                baseURL: baseURL,
                apiToken: trimmedToken
            )
            try await TrackingClient().health(configuration: configuration)

            try KeychainService.shared.saveTrackingAPIToken(
                trimmedToken,
                forAPIBaseURL: baseURL.absoluteString
            )
            apiToken = trimmedToken
            hasStoredToken = true
            apiBaseURL = baseURL.absoluteString
            status = .connected
        } catch {
            status = .failure("Connection failed. Check the domain, token, and server status.")
        }
    }

    private func disableTrackingIfConfigurationIsIncomplete() {
        if normalizedBaseURL == nil || !hasStoredToken {
            isTrackingEnabled = false
        }
    }
}

private struct TrackingEndpointSection: View {
    @Binding var apiBaseURL: String
    @Binding var apiToken: String

    let hasStoredToken: Bool
    let isTestingConnection: Bool
    let canTestConnection: Bool
    let status: TrackingSettingsStatus?
    let saveToken: () -> Void
    let removeToken: () -> Void
    let testConnection: () -> Void

    var body: some View {
        Section("Tracking Service") {
            TextField("API domain", text: $apiBaseURL, prompt: Text("https://tracking.example.com"))
                .textContentType(.URL)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #elseif os(macOS)
                .textFieldStyle(.roundedBorder)
                #endif

            SecureField("API token", text: $apiToken)
                .textContentType(.password)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #elseif os(macOS)
                .textFieldStyle(.roundedBorder)
                #endif

            HStack {
                Button("Save Token", action: saveToken)
                    .disabled(apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Test Connection", action: testConnection)
                    .disabled(!canTestConnection || isTestingConnection)

                if isTestingConnection {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let status {
                Label(status.message, systemImage: status.systemImage)
                    .foregroundStyle(status.color)
                    .font(.caption)
            } else if hasStoredToken {
                Label("API token stored in Keychain", systemImage: "checkmark.shield")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            if hasStoredToken {
                Button("Remove API Token", role: .destructive, action: removeToken)
            }
        }
    }
}

private struct TrackingInteractionSection: View {
    @Binding var isTrackingEnabled: Bool
    let canEnableTracking: Bool

    var body: some View {
        Section("Interaction Tracking") {
            Toggle("Track interaction", isOn: $isTrackingEnabled)
                .disabled(!canEnableTracking)

            Text("When enabled, recipient-facing redemption links use your tracking service. Opening a link records Seen before redirecting to Apple.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !canEnableTracking {
                Text("Add a valid HTTPS API domain and save an API token to enable tracking.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct TrackingPrivacySection: View {
    var body: some View {
        Section("Privacy and Hosting") {
            Text("CodeVault does not provide or operate a tracking service. Use a backend you control. The API token is stored in this device's Keychain and is never bundled with the open-source app.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Seen means the redirect was requested. Mail scanners and link previews can trigger it, so it does not prove a person opened or redeemed the code.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private enum TrackingSettingsStatus {
    case saved
    case removed
    case connected
    case failure(String)

    var message: String {
        switch self {
        case .saved:
            return "API token saved"
        case .removed:
            return "API token removed"
        case .connected:
            return "Connection successful"
        case .failure(let message):
            return message
        }
    }

    var systemImage: String {
        switch self {
        case .saved, .connected:
            return "checkmark.circle.fill"
        case .removed:
            return "trash.circle.fill"
        case .failure:
            return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .saved, .connected:
            return .green
        case .removed:
            return .secondary
        case .failure:
            return .red
        }
    }
}

#Preview {
    NavigationStack {
        TrackingSettingsView()
    }
}
