//
//  PlatformUtilities.swift
//  AppStoreCodes
//
//  Created by Matteo Comisso on 08/12/2025.
//

import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Cross-Platform Clipboard

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

// MARK: - Cross-Platform URL Opener

enum PlatformURLOpener {
    static func open(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }

    static func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        open(url)
    }
}

// MARK: - Platform Detection

enum Platform {
    static var isMac: Bool {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }

    static var isIOS: Bool {
        #if os(iOS)
        return true
        #else
        return false
        #endif
    }
}
