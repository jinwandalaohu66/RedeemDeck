import SwiftUI

struct CodeRetrievalTextRows: View {
    let codes: [PreparedCode]
    let output: RetrievalOutput
    let onCopy: (PreparedCode) -> Void

    @State private var copiedCodeID: UUID?

    var body: some View {
        ForEach(codes) { code in
            HStack(spacing: 12) {
                Text(output == .codes ? code.code : code.redemptionURL)
                    .font(output == .codes ? .body.monospaced() : .callout.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                Button {
                    showCopiedState(for: code)
                    onCopy(code)
                } label: {
                    Image(systemName: copiedCodeID == code.id ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(copyAccessibilityLabel(for: code))
            }
        }
    }

    private func copyAccessibilityLabel(for code: PreparedCode) -> String {
        guard copiedCodeID != code.id else { return String(localized: "Copied") }
        return output == .codes ? String(localized: "Copy Code") : String(localized: "Copy Link")
    }

    private func showCopiedState(for code: PreparedCode) {
        copiedCodeID = code.id
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled, copiedCodeID == code.id else { return }
            withAnimation { copiedCodeID = nil }
        }
    }
}
