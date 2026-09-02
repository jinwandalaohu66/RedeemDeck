import SwiftUI
import UniformTypeIdentifiers

struct QRCodeSheet: View {
    let content: QRPosterContent
    let appID: UUID
    let repository: CodeVaultRepository

    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    @Environment(AppFeedbackCenter.self) private var feedback
    @State private var greeting: String
    @State private var greetingDraft: String
    @State private var poster: GeneratedQRPoster?
    @State private var isEditingGreeting = false
    @State private var isSaving = false
    @State private var isExporting = false
    @State private var errorMessage: String?

    init(
        content: QRPosterContent,
        appID: UUID,
        repository: CodeVaultRepository
    ) {
        self.content = content
        self.appID = appID
        self.repository = repository
        _greeting = State(initialValue: content.greeting)
        _greetingDraft = State(initialValue: content.greeting)
    }

    private var currentContent: QRPosterContent {
        QRPosterContent(
            redemptionURL: content.redemptionURL,
            appName: content.appName,
            expirationDate: content.expirationDate,
            greeting: greeting,
            iconURL: content.iconURL
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    posterArtwork
                    Button("Edit Greeting", systemImage: "pencil") {
                        greetingDraft = greeting
                        isEditingGreeting = true
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .padding(.horizontal)
            }
            .navigationTitle("Redemption Poster")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
            .codeVaultBottomAction { saveButton }
            .task(id: currentContent) { await generate() }
            .fileExporter(
                isPresented: $isExporting,
                document: QRCodeImageDocument(data: poster?.pngData ?? Data()),
                contentType: .png,
                defaultFilename: "\(content.appName) Redemption Poster",
                onCompletion: handleExport
            )
            .alert("Edit Greeting", isPresented: $isEditingGreeting) {
                TextField("Greeting", text: $greetingDraft)
                Button("Save", action: saveGreeting)
                Button("Cancel", role: .cancel) { greetingDraft = greeting }
            } message: {
                Text("This message appears on every redemption poster for this App.")
            }
            .alert(
                "Unable to Save Poster",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? String(localized: "The poster could not be saved."))
            }
        }
        .appFeedbackPresenter()
        .codeVaultFormPresentation()
    }

    @ViewBuilder
    private var posterArtwork: some View {
        if let poster {
            Image(decorative: poster.image, scale: 1)
                .resizable()
                .scaledToFit()
                .shadow(color: .black.opacity(0.1), radius: 14, y: 6)
                .frame(maxWidth: 300)
                .accessibilityLabel("Redemption Poster")
        } else {
            ProgressView("Generating Poster")
                .frame(maxWidth: .infinity, minHeight: 400)
        }
    }

    private var saveButton: some View {
        Button(action: save) {
            Label(saveButtonTitle, systemImage: "square.and.arrow.down")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
        }
        .controlSize(.regular)
        .buttonBorderShape(.capsule)
        .codeVaultPrimaryButtonStyle()
        .disabled(poster == nil || isSaving)
    }

    private var saveButtonTitle: String {
        #if os(iOS)
        String(localized: "Save to Photos")
        #else
        String(localized: "Save Image")
        #endif
    }

    private func generate() async {
        poster = nil
        do {
            poster = try await QRCodeService.shared.makePoster(from: currentContent)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = String(localized: "The poster could not be generated.")
        }
    }

    private func saveGreeting() {
        let storedValue = greetingDraft.nilIfBlank
        greeting = storedValue ?? String(localized: "A little gift for you. Enjoy!")
        Task {
            do {
                try await repository.updateAppGreeting(id: appID, greeting: storedValue)
                session.dataDidChange()
                feedback.show(String(localized: "Greeting saved."))
            } catch {
                errorMessage = UserFacingError.message(for: error)
            }
        }
    }

    private func save() {
        guard let poster else { return }
        isSaving = true
        #if os(iOS)
        Task {
            defer { isSaving = false }
            do {
                try await PhotoLibrarySaver.shared.savePNGData(poster.pngData)
                feedback.show(String(localized: "Poster saved to Photos."))
            } catch {
                errorMessage = String(localized: "Allow photo access in Settings, then try again.")
            }
        }
        #else
        isExporting = true
        isSaving = false
        #endif
    }

    private func handleExport(_ result: Result<URL, Error>) {
        if case .success = result {
            feedback.show(String(localized: "Poster saved."))
        } else if case .failure = result {
            errorMessage = String(localized: "The poster could not be saved.")
        }
    }
}

private struct QRCodeImageDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.png] }
    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
