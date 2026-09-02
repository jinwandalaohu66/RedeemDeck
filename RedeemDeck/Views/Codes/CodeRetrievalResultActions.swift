import Foundation

extension CodeRetrievalResultView {
    var codeText: String {
        selection.codes.map(\.code).joined(separator: "\n")
    }

    var linkText: String {
        selection.codes.map(\.redemptionURL).joined(separator: "\n")
    }

    var posterContents: [QRPosterContent] {
        selection.codes.map { code in
            QRPosterContent(
                redemptionURL: code.redemptionURL,
                appName: selection.appName,
                expirationDate: code.expirationDate,
                greeting: greeting,
                iconURL: selection.appIconURL
            )
        }
    }

    func performPrimaryAction() {
        switch output {
        case .codes:
            copyAll(
                codeText,
                singularKind: String(localized: "Code"),
                pluralKind: String(localized: "Codes")
            )
        case .links:
            copyAll(
                linkText,
                singularKind: String(localized: "Link"),
                pluralKind: String(localized: "Links")
            )
        case .qrCodes:
            #if os(iOS)
            saveQRCodes()
            #else
            copyAll(
                linkText,
                singularKind: String(localized: "Link"),
                pluralKind: String(localized: "Links")
            )
            #endif
        }
    }

    func copy(_ code: PreparedCode, as output: RetrievalOutput) {
        let value = output == .codes ? code.code : code.redemptionURL
        PlatformClipboard.copy(value)
        guard code.status == .pending else {
            feedback.show(String(localized: "Copied."), tone: .information)
            return
        }
        Task {
            do {
                try await repository.markCodeSent(id: code.id)
                try await reloadSelection()
                showSentFeedback(
                    String(localized: "Copied."),
                    changedCodeIDs: [code.id]
                )
            } catch {
                errorMessage = UserFacingError.message(for: error)
            }
        }
    }

    func copyAll(_ value: String, singularKind: String, pluralKind: String) {
        PlatformClipboard.copy(value)
        let kind = selection.codes.count == 1 ? singularKind : pluralKind
        let message = String(localized: "Copied \(selection.codes.count) \(kind).")
        guard selection.isPending else {
            feedback.show(message, tone: .information)
            return
        }
        markPendingAsSent(successMessage: message)
    }

    func markPendingAsSent(successMessage: String? = nil) {
        let pendingIDs = selection.codes
            .filter { $0.status == .pending }
            .map(\.id)
        guard !pendingIDs.isEmpty else {
            if let successMessage { feedback.show(successMessage, tone: .information) }
            return
        }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await commitPendingAsSent(
                    successMessage ?? String(localized: "Marked as sent."),
                    pendingIDs: pendingIDs
                )
            } catch {
                errorMessage = UserFacingError.message(for: error)
            }
        }
    }

    func commitPendingAsSent(
        _ successMessage: String,
        pendingIDs: [UUID]
    ) async throws {
        selection = try await repository.markSelectionSent(id: selection.id)
        session.dataDidChange()
        showSentFeedback(successMessage, changedCodeIDs: pendingIDs)
    }

    func showSentFeedback(_ message: String, changedCodeIDs: [UUID]) {
        feedback.show(message, actionTitle: String(localized: "Undo")) {
            undoSentStatus(codeIDs: changedCodeIDs)
        }
    }

    func undoSentStatus(codeIDs: [UUID]) {
        Task {
            do {
                try await repository.restoreCodesToPending(
                    retrievalID: selection.id,
                    codeIDs: codeIDs
                )
                try await reloadSelection()
                feedback.show(String(localized: "Returned to pending."))
            } catch {
                feedback.show(
                    String(localized: "The code status could not be updated."),
                    tone: .information
                )
            }
        }
    }

    func reloadSelection() async throws {
        guard let refreshed = try await repository.loadSelection(id: selection.id) else {
            throw RedeemDeckRepositoryError.selectionNotFound
        }
        selection = refreshed
        session.dataDidChange()
    }

    #if os(iOS)
    func saveQRCodes() {
        let pendingIDs = selection.codes
            .filter { $0.status == .pending }
            .map(\.id)
        isWorking = true
        Task {
            defer { isWorking = false }
            let data: [Data]
            do {
                data = try await QRCodeService.shared.makePosterPNGData(contents: posterContents)
                try await PhotoLibrarySaver.shared.savePNGData(data)
            } catch {
                errorMessage = String(localized: "Allow photo access in Settings, then try again.")
                return
            }

            let message = String(localized: "Saved \(data.count) Posters to Photos.")
            guard !pendingIDs.isEmpty else {
                feedback.show(message, tone: .information)
                return
            }
            do {
                try await commitPendingAsSent(message, pendingIDs: pendingIDs)
            } catch {
                errorMessage = UserFacingError.message(for: error)
            }
        }
    }
    #endif
}
