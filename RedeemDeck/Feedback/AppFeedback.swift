import Observation
import SwiftUI

enum AppFeedbackTone: Sendable {
    case success
    case information

    var symbolName: String {
        switch self {
        case .success: "checkmark.circle.fill"
        case .information: "info.circle.fill"
        }
    }
}

struct AppFeedbackMessage: Identifiable {
    let id = UUID()
    let text: String
    let tone: AppFeedbackTone
    let actionTitle: String?
}

@MainActor
@Observable
final class AppFeedbackCenter {
    private(set) var message: AppFeedbackMessage?
    private(set) var successPulse = 0
    private(set) var informationPulse = 0
    private var dismissalTask: Task<Void, Never>?
    private var action: (() -> Void)?

    func show(
        _ text: String,
        tone: AppFeedbackTone = .success,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        dismissalTask?.cancel()
        self.action = action
        message = AppFeedbackMessage(
            text: text,
            tone: tone,
            actionTitle: actionTitle
        )
        switch tone {
        case .success: successPulse &+= 1
        case .information: informationPulse &+= 1
        }

        let messageID = message?.id
        dismissalTask = Task { [weak self] in
            try? await Task.sleep(for: actionTitle == nil ? .seconds(2.2) : .seconds(5))
            guard !Task.isCancelled, self?.message?.id == messageID else { return }
            self?.dismiss()
        }
    }

    func performAction() {
        let action = action
        dismiss()
        action?()
    }

    func dismiss() {
        dismissalTask?.cancel()
        message = nil
        action = nil
    }
}

struct AppFeedbackOverlay: View {
    @Environment(AppFeedbackCenter.self) private var feedback

    var body: some View {
        Group {
            if let message = feedback.message {
                HStack(spacing: 12) {
                    Label(message.text, systemImage: message.tone.symbolName)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let actionTitle = message.actionTitle {
                        Spacer(minLength: 4)
                        Button(actionTitle, action: feedback.performAction)
                            .fontWeight(.semibold)
                    }
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .feedbackSurface()
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityElement(children: .contain)
            }
        }
        .animation(.snappy, value: feedback.message?.id)
        #if os(iOS)
        .sensoryFeedback(.success, trigger: feedback.successPulse)
        .sensoryFeedback(.selection, trigger: feedback.informationPulse)
        #endif
    }
}

private extension View {
    @ViewBuilder
    func feedbackSurface() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            glassEffect(.regular, in: Capsule())
        } else {
            background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        }
    }
}
