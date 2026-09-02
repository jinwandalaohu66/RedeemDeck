import SwiftUI

struct CodeRetrievalResultView: View {
    @Binding var selection: PreparedCodeSelection
    let repository: CodeVaultRepository

    @Environment(AppSession.self) var session
    @Environment(AppFeedbackCenter.self) var feedback
    @State var output = RetrievalOutput.codes
    @State var isWorking = false
    @State var errorMessage: String?
    @State var greeting: String
    @State private var greetingDraft: String
    @State private var isEditingGreeting = false

    init(
        selection: Binding<PreparedCodeSelection>,
        repository: CodeVaultRepository
    ) {
        _selection = selection
        self.repository = repository
        let value = selection.wrappedValue.appGreeting?.nilIfBlank
            ?? String(localized: "A little gift for you. Enjoy!")
        _greeting = State(initialValue: value)
        _greetingDraft = State(initialValue: value)
    }

    var body: some View {
        VStack(spacing: 0) {
            outputPicker
            resultContent
        }
        #if os(iOS)
        .background(Color(uiColor: .systemGroupedBackground))
        #else
        .background(Color(nsColor: .windowBackgroundColor))
        #endif
        .codeVaultBottomAction { primaryButton }
        .disabled(isWorking)
        .overlay { if isWorking { ProgressView("Working") } }
        .alert("Edit Greeting", isPresented: $isEditingGreeting) {
            TextField("Greeting", text: $greetingDraft)
            Button("Save", action: saveGreeting)
            Button("Cancel", role: .cancel) { greetingDraft = greeting }
        } message: {
            Text("This message appears on every redemption poster for this App.")
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

    private var outputPicker: some View {
        Picker("Output", selection: $output) {
            ForEach(RetrievalOutput.allCases) { value in
                Text(value.localizedName).tag(value)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var resultContent: some View {
        ZStack {
            textList(for: .codes)
                .opacity(output == .codes ? 1 : 0)
                .allowsHitTesting(output == .codes)
                .accessibilityHidden(output != .codes)

            textList(for: .links)
                .opacity(output == .links ? 1 : 0)
                .allowsHitTesting(output == .links)
                .accessibilityHidden(output != .links)

            CodeRetrievalQRCodeView(
                codes: selection.codes,
                appName: selection.appName,
                iconURL: selection.appIconURL,
                greeting: greeting,
                onEditGreeting: beginEditingGreeting
            )
            .opacity(output == .qrCodes ? 1 : 0)
            .allowsHitTesting(output == .qrCodes)
            .accessibilityHidden(output != .qrCodes)
        }
        .animation(nil, value: output)
    }

    private func textList(for value: RetrievalOutput) -> some View {
        List {
            Section {
                CodeRetrievalTextRows(
                    codes: selection.codes,
                    output: value,
                    onCopy: { copy($0, as: value) }
                )
            }
        }
        .codeVaultGroupedListStyle()
        .codeVaultScrollEdgeStyle()
    }

    private var primaryButton: some View {
        Button(action: performPrimaryAction) {
            Label(primaryButtonTitle, systemImage: primaryButtonIcon)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
        }
        .controlSize(.regular)
        .buttonBorderShape(.capsule)
        .codeVaultPrimaryButtonStyle()
        .disabled(isWorking)
    }

    private var primaryButtonTitle: String {
        switch output {
        case .codes:
            selection.codes.count == 1
                ? String(localized: "Copy")
                : String(localized: "Copy \(selection.codes.count)")
        case .links:
            selection.codes.count == 1
                ? String(localized: "Copy")
                : String(localized: "Copy \(selection.codes.count)")
        case .qrCodes:
            #if os(iOS)
            selection.codes.count == 1
                ? String(localized: "Save")
                : String(localized: "Save \(selection.codes.count)")
            #else
            selection.codes.count == 1
                ? String(localized: "Copy")
                : String(localized: "Copy \(selection.codes.count)")
            #endif
        }
    }

    private var primaryButtonIcon: String {
        switch output {
        case .codes, .links: "doc.on.doc"
        case .qrCodes: "square.and.arrow.down"
        }
    }

    private func beginEditingGreeting() {
        greetingDraft = greeting
        isEditingGreeting = true
    }

    private func saveGreeting() {
        let storedValue = greetingDraft.nilIfBlank
        greeting = storedValue ?? String(localized: "A little gift for you. Enjoy!")
        Task {
            do {
                try await repository.updateAppGreeting(
                    id: selection.appID,
                    greeting: storedValue
                )
                try await reloadSelection()
                feedback.show(String(localized: "Greeting saved."))
            } catch {
                errorMessage = UserFacingError.message(for: error)
            }
        }
    }
}
