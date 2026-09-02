import SwiftUI

struct CodeCategoryRow: View {
    let category: CodeCategorySummary

    private var available: Int { category.availableCount }
    private var total: Int { category.totalCount }

    var body: some View {
        HStack(spacing: 12) {
            Text(category.name)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(compact(available))/\(compact(total))")
                .font(.body.monospacedDigit().weight(.medium))
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(category.name)
        .accessibilityValue("\(available) available out of \(total) codes")
    }

    private func compact(_ count: Int) -> String {
        count.formatted(.number.notation(.compactName))
    }
}
