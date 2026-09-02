import Foundation

extension LibraryView {
    func showFileImporter() { isShowingFileImporter = true }
    func showAddApp() { isShowingAddApp = true }

    func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            inspect(url)
        case .failure:
            errorMessage = String(localized: "The selected file could not be opened.")
        }
    }

    func inspect(_ url: URL) {
        isInspecting = true
        Task {
            defer { isInspecting = false }
            do {
                let inspection = try await csvImporter.inspect(url)
                pendingImport = ImportDraft(url: url, inspection: inspection)
            } catch {
                errorMessage = UserFacingError.message(for: error)
            }
        }
    }

    func finishImport(_ result: CSVImportResult) {
        pendingImport = nil
        feedback.show(ImportOutcome(result: result).message)
        session.dataDidChange()
    }

    func showAppSaved(isNew: Bool) {
        feedback.show(
            isNew ? String(localized: "App added.") : String(localized: "App updated.")
        )
    }

    func archiveSelectedApp() {
        guard let app = archiveCandidate else { return }
        archiveCandidate = nil
        Task {
            do {
                try await repository.setArchived(.app(app.id), archived: true)
                session.dataDidChange()
                feedback.show(String(localized: "App archived."))
            } catch {
                errorMessage = UserFacingError.message(for: error)
            }
        }
    }

    func loadDashboard() async {
        async let inventoryRequest = dashboardRepository.loadLibraryInventory()
        async let pendingRequest = repository.loadPendingSelections()
        let inventory = try? await inventoryRequest
        let pending = try? await pendingRequest
        guard !Task.isCancelled else { return }
        inventoryByApp = Dictionary(uniqueKeysWithValues: (inventory ?? []).map { ($0.id, $0) })
        pendingSelections = pending ?? []
    }

    func refreshMissingArtwork() async {
        guard !didRefreshArtwork else { return }
        didRefreshArtwork = true
        let missing = apps
            .filter { $0.iconURL == nil && $0.appStoreId.allSatisfy(\.isNumber) }
            .prefix(12)
            .map { ($0.id, $0.appStoreId) }
        var didUpdate = false
        for (id, appStoreID) in missing {
            guard !Task.isCancelled else { return }
            guard let metadata = try? await AppStoreLookupService.shared.lookupApp(byID: appStoreID) else {
                continue
            }
            if (try? await repository.backfillAppMetadata(id: id, metadata: metadata)) != nil {
                didUpdate = true
            }
        }
        if didUpdate { session.dataDidChange() }
    }
}
