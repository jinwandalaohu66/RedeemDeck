import SwiftUI

struct CodeDetailView: View {
    let code: CodeRowSummary
    let app: AppSummary
    let categoryName: String
    let productName: String
    let repository: CodeVaultRepository

    @Environment(AppSession.self) private var session
    @Environment(AppFeedbackCenter.self) private var feedback
    @State private var didCopy = false
    @State private var isShowingQRCode = false
    @State private var isUpdating = false
    @State private var errorMessage: String?
    @State private var status: CodeLifecycleStatus
    #if os(iOS)
    @State private var shareRequest: ActivityShareRequest?
    #endif

    init(
        code: CodeRowSummary,
        app: AppSummary,
        categoryName: String,
        productName: String,
        repository: CodeVaultRepository
    ) {
        self.code = code
        self.app = app
        self.categoryName = categoryName
        self.productName = productName
        self.repository = repository
        _status = State(initialValue: code.status)
    }

    var body: some View {
        Form {
            codeSection
            actionSection
            statusSection
            informationSection
        }
        .navigationTitle("Code Details")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .codeVaultScrollEdgeStyle()
        .disabled(isUpdating)
        .overlay { if isUpdating { ProgressView() } }
        .sheet(isPresented: $isShowingQRCode) {
            QRCodeSheet(
                content: QRPosterContent(
                    redemptionURL: code.redemptionURL,
                    appName: app.name,
                    expirationDate: code.expirationDate,
                    greeting: app.qrGreeting?.nilIfBlank
                        ?? String(localized: "A little gift for you. Enjoy!"),
                    iconURL: app.iconURL
                ),
                appID: app.id,
                repository: repository
            )
        }
        #if os(iOS)
        .sheet(item: $shareRequest) { request in
            SystemActivitySheet(request: request) { completed in
                completeShare(completed: completed)
            }
        }
        #endif
        .alert(
            "Unable to Update Code",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? String(localized: "The code status could not be updated."))
        }
    }

    private var codeSection: some View {
        Section {
            HStack(spacing: 12) {
                Text(code.code)
                    .font(.title3.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                Button(action: copyCode) {
                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(didCopy ? "Copied" : "Copy Code")
            }
        }
    }

    private var actionSection: some View {
        Section {
            #if os(iOS)
            Button("Share Redemption Link") {
                shareRequest = ActivityShareRequest(
                    items: [code.redemptionURL],
                    temporaryDirectory: nil
                )
            }
            #else
            ShareLink(item: code.redemptionURL) {
                Text("Share Redemption Link")
            }
            .simultaneousGesture(TapGesture().onEnded(markShared))
            #endif
            Button("Show QR Code") { isShowingQRCode = true }
        }
    }

    private var statusSection: some View {
        Section {
            HStack {
                Text("Status")
                Spacer()
                if status == .expired {
                    Text(status.localizedName)
                        .foregroundStyle(.secondary)
                } else {
                    Menu {
                        statusActions
                    } label: {
                        Text(status.localizedName)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var statusActions: some View {
        switch status {
        case .available:
            Button("Mark as Sent") { updateStatus(.sent) }
        case .pending:
            Button("Mark as Sent") { updateStatus(.sent) }
            Button("Make Available Again") { updateStatus(.available) }
        case .sent:
            Button("Make Available Again") { updateStatus(.available) }
        case .expired:
            EmptyView()
        }
    }

    private var informationSection: some View {
        Section("Information") {
            LabeledContent("Product", value: productName)
            LabeledContent("Code Category", value: categoryName)
            if let expirationDate = code.expirationDate {
                LabeledContent("Expires") {
                    Text(expirationDate, format: .dateTime.year().month().day())
                }
            }
            if let notes = code.notes, !notes.isEmpty {
                Text(notes)
            }
        }
    }

    private func copyCode() {
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            withAnimation { didCopy = false }
        }
        CodeCopyAction.perform(
            codeID: code.id,
            value: code.code,
            status: status,
            repository: repository,
            session: session,
            feedback: feedback,
            onMarkedSent: { status = $0 },
            onUndo: { status = $0 }
        )
    }

    private func markShared() {
        guard status == .available || status == .pending else {
            return
        }
        CodeCopyAction.markAsSent(
            codeID: code.id,
            repository: repository,
            session: session,
            feedback: feedback,
            successMessage: String(localized: "Code marked as sent."),
            undoTarget: status,
            onMarkedSent: { status = $0 },
            onUndo: { status = $0 }
        )
    }

    #if os(iOS)
    private func completeShare(completed: Bool) {
        if completed {
            markShared()
        } else {
            feedback.show(String(localized: "Share cancelled."), tone: .information)
        }
    }
    #endif

    private func updateStatus(_ action: CodeStatusAction) {
        isUpdating = true
        Task {
            do {
                status = try await repository.updateCodeStatus(id: code.id, action: action)
                session.dataDidChange()
                feedback.show(String(localized: "Code status updated."))
            } catch {
                errorMessage = UserFacingError.message(for: error)
            }
            isUpdating = false
        }
    }
}
