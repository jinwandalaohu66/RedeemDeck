import Foundation

@MainActor
enum CodeCopyAction {
    static func perform(
        codeID: UUID,
        value: String,
        status: CodeLifecycleStatus,
        repository: RedeemDeckRepository,
        session: AppSession,
        feedback: AppFeedbackCenter,
        onMarkedSent: @escaping (CodeLifecycleStatus) -> Void = { _ in },
        onUndo: @escaping (CodeLifecycleStatus) -> Void = { _ in }
    ) {
        PlatformClipboard.copy(value)
        guard status == .available || status == .pending else {
            feedback.show(String(localized: "Copied."), tone: .information)
            return
        }

        markAsSent(
            codeID: codeID,
            repository: repository,
            session: session,
            feedback: feedback,
            successMessage: String(localized: "Copied."),
            undoTarget: status,
            onMarkedSent: onMarkedSent,
            onUndo: onUndo
        )
    }

    static func markAsSent(
        codeID: UUID,
        repository: RedeemDeckRepository,
        session: AppSession,
        feedback: AppFeedbackCenter,
        successMessage: String,
        undoTarget: CodeLifecycleStatus = .available,
        onMarkedSent: @escaping (CodeLifecycleStatus) -> Void = { _ in },
        onUndo: @escaping (CodeLifecycleStatus) -> Void = { _ in }
    ) {
        Task {
            do {
                let status = try await repository.markCodeSent(id: codeID)
                session.dataDidChange()
                onMarkedSent(status)
                feedback.show(
                    successMessage,
                    actionTitle: String(localized: "Undo")
                ) {
                    undoSentStatus(
                        codeID: codeID,
                        repository: repository,
                        session: session,
                        feedback: feedback,
                        undoTarget: undoTarget,
                        onUndo: onUndo
                    )
                }
            } catch {
                feedback.show(
                    String(localized: "The code status could not be updated."),
                    tone: .information
                )
            }
        }
    }

    private static func undoSentStatus(
        codeID: UUID,
        repository: RedeemDeckRepository,
        session: AppSession,
        feedback: AppFeedbackCenter,
        undoTarget: CodeLifecycleStatus,
        onUndo: @escaping (CodeLifecycleStatus) -> Void
    ) {
        Task {
            do {
                let status: CodeLifecycleStatus
                if undoTarget == .pending {
                    status = try await repository.restoreCodeToPending(id: codeID)
                } else {
                    status = try await repository.updateCodeStatus(id: codeID, action: .available)
                }
                session.dataDidChange()
                onUndo(status)
                feedback.show(
                    status == .pending
                        ? String(localized: "Returned to pending.")
                        : String(localized: "Code returned to available.")
                )
            } catch {
                feedback.show(
                    String(localized: "The code could not be returned to available."),
                    tone: .information
                )
            }
        }
    }
}
