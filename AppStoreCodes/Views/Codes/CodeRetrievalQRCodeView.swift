import SwiftUI

struct CodeRetrievalQRCodeView: View {
    let codes: [PreparedCode]
    let appName: String
    let iconURL: String?
    let greeting: String
    let onEditGreeting: () -> Void

    @State private var topIndex = 0
    @State private var dragOffset = CGSize.zero
    @State private var isDismissingTopCard = false

    private var pageNumber: Int {
        guard !codes.isEmpty else { return 0 }
        return min(topIndex, codes.count - 1) + 1
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                posterDeck

                if codes.count > 1 {
                    Text("\(pageNumber) / \(codes.count)")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .accessibilityLabel("QR code \(pageNumber) of \(codes.count)")
                }

                Button("Edit Greeting", systemImage: "pencil", action: onEditGreeting)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .onChange(of: codes.count) { _, count in
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                topIndex = count == 0 ? 0 : min(topIndex, count - 1)
                dragOffset = .zero
                isDismissingTopCard = false
            }
        }
        #if os(iOS)
        .sensoryFeedback(.selection, trigger: topIndex)
        #endif
    }

    private var posterDeck: some View {
        ZStack {
            ForEach(stackItems.reversed()) { item in
                let visualDepth = visualDepth(for: item.depth)
                let isTopCard = item.depth == 0

                CodeRetrievalPosterPage(
                    content: QRPosterContent(
                        redemptionURL: item.code.redemptionURL,
                        appName: appName,
                        expirationDate: item.code.expirationDate,
                        greeting: greeting,
                        iconURL: iconURL
                    )
                )
                .scaleEffect(scale(for: visualDepth))
                .rotationEffect(rotation(for: visualDepth, isTopCard: isTopCard))
                .offset(offset(for: visualDepth, isTopCard: isTopCard))
                .zIndex(Double(visibleCardLimit - item.depth))
                .contentShape(.rect)
                .allowsHitTesting(isTopCard && !isDismissingTopCard)
                .accessibilityHidden(!isTopCard)
                .accessibilityHint(
                    Text(codes.count > 1
                         ? String(localized: "Swipe left or right to see the next poster.")
                         : "")
                )
                .gesture(
                    topCardDragGesture,
                    including: isTopCard && codes.count > 1 ? .all : .none
                )
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 438)
    }

    private let visibleCardLimit = 3

    private var stackItems: [PosterStackItem] {
        guard !codes.isEmpty else { return [] }
        let count = min(codes.count, visibleCardLimit)
        return (0..<count).map { depth in
            let index = (topIndex + depth) % codes.count
            return PosterStackItem(code: codes[index], depth: depth)
        }
    }

    private func visualDepth(for depth: Int) -> CGFloat {
        if isDismissingTopCard, depth > 0 {
            return CGFloat(depth - 1)
        }
        return CGFloat(depth)
    }

    private func scale(for depth: CGFloat) -> CGFloat {
        1 - (depth * 0.008)
    }

    private func rotation(for depth: CGFloat, isTopCard: Bool) -> Angle {
        if isTopCard {
            return .degrees(Double(dragOffset.width / 28))
        }
        guard depth > 0 else { return .zero }
        return .degrees(depth == 1 ? -1.7 : 1.7)
    }

    private func offset(for depth: CGFloat, isTopCard: Bool) -> CGSize {
        if isTopCard {
            return dragOffset
        }
        guard depth > 0 else { return .zero }
        let xOffset: CGFloat = depth == 1 ? -10 : 10
        return CGSize(width: xOffset, height: depth * 10)
    }

    private var topCardDragGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard !isDismissingTopCard else { return }
                dragOffset = CGSize(
                    width: value.translation.width,
                    height: value.translation.height * 0.18
                )
            }
            .onEnded(handleDragEnded)
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        guard !isDismissingTopCard, codes.count > 1 else { return }

        let measured = value.translation.width
        let predicted = value.predictedEndTranslation.width
        guard abs(measured) >= 72 || abs(predicted) >= 140 else {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                dragOffset = .zero
            }
            return
        }

        let directionSource = abs(predicted) > abs(measured) ? predicted : measured
        let direction: CGFloat = directionSource >= 0 ? 1 : -1
        let exitOffset = CGSize(
            width: direction * 900,
            height: max(-60, min(60, value.translation.height * 0.25))
        )

        withAnimation(
            .snappy(duration: 0.28, extraBounce: 0),
            completionCriteria: .logicallyComplete
        ) {
            isDismissingTopCard = true
            dragOffset = exitOffset
        } completion: {
            advanceDeck()
        }
    }

    private func advanceDeck() {
        guard !codes.isEmpty else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            topIndex = (topIndex + 1) % codes.count
            dragOffset = .zero
            isDismissingTopCard = false
        }
    }
}

private struct PosterStackItem: Identifiable {
    let code: PreparedCode
    let depth: Int

    var id: UUID { code.id }
}

private struct CodeRetrievalPosterPage: View {
    let content: QRPosterContent
    @State private var poster: GeneratedQRPoster?
    @State private var failed = false
    @State private var retryToken = 0

    var body: some View {
        posterContent
            .frame(width: 300, height: 400)
            .task(id: PosterGenerationKey(content: content, retryToken: retryToken)) {
                await generate()
            }
    }

    @ViewBuilder
    private var posterContent: some View {
        if let poster {
            Image(decorative: poster.image, scale: 1)
                .resizable()
                .scaledToFit()
                .frame(width: 300, height: 400)
                .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
                .accessibilityLabel("Redemption Poster")
        } else if failed {
            ContentUnavailableView {
                Label("Unable to Generate Poster", systemImage: "qrcode")
            } actions: {
                Button("Try Again") { retryToken &+= 1 }
            }
            .frame(width: 300, height: 400)
        } else {
            ProgressView("Generating Poster")
                .frame(width: 300, height: 400)
        }
    }

    private func generate() async {
        failed = false
        do {
            poster = try await QRCodeService.shared.makePoster(from: content)
        } catch is CancellationError {
            return
        } catch {
            failed = true
        }
    }
}

private struct PosterGenerationKey: Hashable {
    let content: QRPosterContent
    let retryToken: Int
}
