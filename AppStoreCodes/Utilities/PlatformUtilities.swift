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

// MARK: - Share Message Helper

enum ShareMessageHelper {
    static func formatMessage(template: String, appName: String?, url: String, code: String) -> String {
        var message = template
        message = message.replacingOccurrences(of: "{appName}", with: appName ?? "this app")
        message = message.replacingOccurrences(of: "{url}", with: url)
        message = message.replacingOccurrences(of: "{code}", with: code)
        return message
    }
}

// MARK: - QR Code Generator

import CoreImage.CIFilterBuiltins

enum QRCodeGenerator {
    static func generate(from string: String, size: CGFloat = 200) -> Image? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()

        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }

        let scale = size / outputImage.extent.size.width
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }

        #if os(macOS)
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
        return Image(nsImage: nsImage)
        #else
        let uiImage = UIImage(cgImage: cgImage)
        return Image(uiImage: uiImage)
        #endif
    }
}
