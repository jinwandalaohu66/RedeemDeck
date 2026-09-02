import SwiftUI

struct LibraryAppRow: View {
    let app: AppSummary
    let inventory: AppInventorySummary?

    private var available: Int { inventory?.availableCount ?? 0 }
    private var total: Int { inventory?.totalCount ?? 0 }

    var body: some View {
        HStack(spacing: 12) {
            AppArtworkView(iconURL: app.iconURL)

            VStack(alignment: .leading) {
                Text(app.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(inventoryDescription)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 8)

            Text("Get")
                .foregroundStyle(.tint)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(app.name)
        .accessibilityValue("\(available) available out of \(total) codes")
    }

    private var inventoryDescription: String {
        let typeCount = inventory?.categoryCount ?? 0
        let typeDescription = typeCount == 1
            ? String(localized: "1 type")
            : String(localized: "\(typeCount) types")
        return "\(compact(available))/\(compact(total)) · \(typeDescription)"
    }

    private func compact(_ count: Int) -> String {
        count.formatted(.number.notation(.compactName))
    }
}
