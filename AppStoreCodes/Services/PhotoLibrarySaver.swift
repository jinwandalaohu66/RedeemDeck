#if os(iOS)
import Foundation
import Photos

nonisolated enum PhotoLibrarySaveError: Error, Sendable {
    case permissionDenied
    case saveFailed
}

actor PhotoLibrarySaver {
    static let shared = PhotoLibrarySaver()

    func savePNGData(_ data: Data) async throws {
        try await savePNGData([data])
    }

    func savePNGData(_ data: [Data]) async throws {
        guard !data.isEmpty else { return }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw PhotoLibrarySaveError.permissionDenied
        }
        try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                for (index, item) in data.enumerated() {
                    let request = PHAssetCreationRequest.forAsset()
                    let options = PHAssetResourceCreationOptions()
                    options.originalFilename = "CodeVault QR \(index + 1).png"
                    request.addResource(with: .photo, data: item, options: options)
                }
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? PhotoLibrarySaveError.saveFailed)
                }
            }
        }
    }
}
#endif
