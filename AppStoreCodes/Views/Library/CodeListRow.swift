import SwiftUI

struct CodeListRow: View {
    let code: CodeRowSummary

    var body: some View {
        HStack(spacing: 12) {
            Text(code.code)
                .font(.body.monospaced())
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(code.status.localizedName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
