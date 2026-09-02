#if os(iOS)
import SwiftUI
import UIKit

struct ActivityShareRequest: Identifiable {
    let id = UUID()
    let items: [Any]
    let temporaryDirectory: URL?
}

struct SystemActivitySheet: UIViewControllerRepresentable {
    let request: ActivityShareRequest
    let onComplete: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: request.items,
            applicationActivities: nil
        )
        controller.completionWithItemsHandler = { _, completed, _, _ in
            onComplete(completed)
        }
        return controller
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}
#endif
