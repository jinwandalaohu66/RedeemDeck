import SwiftUI

struct PendingRetrievalRow: View {
    let item: PendingRetrievalPresentation

    var body: some View {
        HStack(spacing: 12) {
            AppArtworkView(iconURL: item.app.iconURL)
            VStack(alignment: .leading) {
                Text(item.app.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(item.selection.categoryName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("\(item.selection.pendingCount) pending")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Continue \(item.app.name) retrieval")
        .accessibilityValue("\(item.selection.pendingCount) pending codes")
    }
}
