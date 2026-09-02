#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
enum PlatformClipboard {
    static func copy(_ string: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #else
        UIPasteboard.general.string = string
        #endif
    }
}
