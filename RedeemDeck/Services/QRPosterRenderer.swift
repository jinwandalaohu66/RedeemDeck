import CoreGraphics
import CoreText
import Foundation

nonisolated struct QRPosterRenderer {
    private let canvasWidth = CGFloat(QRCodeService.posterWidth)
    private let canvasHeight = CGFloat(QRCodeService.posterHeight)

    func render(
        qrImage: CGImage,
        icon: CGImage?,
        content: QRPosterContent
    ) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: Int(canvasWidth),
            height: Int(canvasHeight),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        prepare(context)
        drawCard(in: context)
        drawHeading(in: context)
        let qrRect = drawQR(qrImage, in: context)
        if let icon {
            draw(icon: icon, in: context, center: CGPoint(x: qrRect.midX, y: qrRect.midY))
        } else {
            drawFallbackIcon(
                appName: content.appName,
                in: context,
                center: CGPoint(x: qrRect.midX, y: qrRect.midY)
            )
        }
        drawDetails(content, in: context)
        return context.makeImage()
    }

    private func prepare(_ context: CGContext) {
        context.clear(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.textMatrix = .identity
    }

    private func drawCard(in context: CGContext) {
        let card = CGRect(x: 28, y: 28, width: canvasWidth - 56, height: canvasHeight - 56)
        context.addPath(CGPath(
            roundedRect: card,
            cornerWidth: 76,
            cornerHeight: 76,
            transform: nil
        ))
        context.setFillColor(CGColor(gray: 0.055, alpha: 1))
        context.fillPath()
    }

    private func drawHeading(in context: CGContext) {
        drawCenteredLine(
            String(localized: "A GIFT FOR YOU"),
            fontSize: 30,
            emphasized: true,
            color: CGColor(gray: 0.68, alpha: 1),
            baselineY: 1_475,
            in: context
        )
    }

    @discardableResult
    private func drawQR(_ qrImage: CGImage, in context: CGContext) -> CGRect {
        let container = CGRect(x: 160, y: 540, width: 880, height: 880)
        context.addPath(CGPath(
            roundedRect: container,
            cornerWidth: 56,
            cornerHeight: 56,
            transform: nil
        ))
        context.setFillColor(CGColor(gray: 1, alpha: 0.96))
        context.fillPath()

        let qrSide: CGFloat = 740
        let qrRect = CGRect(
            x: (canvasWidth - qrSide) / 2,
            y: container.midY - qrSide / 2,
            width: qrSide,
            height: qrSide
        )
        if !RoundedQRCodeRenderer().draw(qrImage, in: qrRect, context: context) {
            context.interpolationQuality = .none
            context.draw(qrImage, in: qrRect)
        }
        return qrRect
    }

    private func drawDetails(_ content: QRPosterContent, in context: CGContext) {
        drawCenteredLines(
            content.appName,
            fontSize: 54,
            emphasized: true,
            color: CGColor(gray: 0.98, alpha: 1),
            maxWidth: 920,
            centerY: 485,
            lineHeight: 62,
            maxLines: 2,
            in: context
        )
        drawCenteredLines(
            content.greeting.nilIfBlank ?? String(localized: "A little gift for you. Enjoy!"),
            fontSize: 38,
            emphasized: false,
            color: CGColor(gray: 0.82, alpha: 1),
            maxWidth: 900,
            centerY: 350,
            lineHeight: 48,
            maxLines: 3,
            in: context
        )
        drawCenteredLine(
            expirationText(for: content.expirationDate),
            fontSize: 30,
            emphasized: false,
            color: CGColor(gray: 0.64, alpha: 1),
            baselineY: 218,
            in: context
        )
        drawCenteredLine(
            String(localized: "Scan to redeem in the App Store"),
            fontSize: 28,
            emphasized: false,
            color: CGColor(gray: 0.52, alpha: 1),
            baselineY: 130,
            in: context
        )
    }

    private func draw(icon: CGImage, in context: CGContext, center: CGPoint) {
        let side: CGFloat = 116
        let rect = CGRect(
            x: center.x - side / 2,
            y: center.y - side / 2,
            width: side,
            height: side
        )
        context.saveGState()
        context.addPath(CGPath(
            roundedRect: rect,
            cornerWidth: 25,
            cornerHeight: 25,
            transform: nil
        ))
        context.clip()
        context.interpolationQuality = .high
        context.draw(icon, in: aspectFillRect(for: icon, inside: rect))
        context.restoreGState()
    }

    private func drawFallbackIcon(
        appName: String,
        in context: CGContext,
        center: CGPoint
    ) {
        let side: CGFloat = 116
        let rect = CGRect(
            x: center.x - side / 2,
            y: center.y - side / 2,
            width: side,
            height: side
        )
        context.addPath(CGPath(
            roundedRect: rect,
            cornerWidth: 25,
            cornerHeight: 25,
            transform: nil
        ))
        context.setFillColor(CGColor(gray: 0.06, alpha: 1))
        context.fillPath()

        let initial = appName.trimmingCharacters(in: .whitespacesAndNewlines).first
            .map { String($0).uppercased() } ?? "A"
        let font = systemFont(size: 60, emphasized: true)
        let line = CTLineCreateWithAttributedString(NSAttributedString(
            string: initial,
            attributes: attributes(font: font, color: CGColor(gray: 1, alpha: 1))
        ))
        let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
        context.textPosition = CGPoint(
            x: center.x - bounds.width / 2 - bounds.minX,
            y: center.y - bounds.height / 2 - bounds.minY
        )
        CTLineDraw(line, context)
    }

    private func drawCenteredLines(
        _ text: String,
        fontSize: CGFloat,
        emphasized: Bool,
        color: CGColor,
        maxWidth: CGFloat,
        centerY: CGFloat,
        lineHeight: CGFloat,
        maxLines: Int,
        in context: CGContext
    ) {
        let font = systemFont(size: fontSize, emphasized: emphasized)
        let attributed = NSAttributedString(string: text, attributes: attributes(
            font: font,
            color: color
        ))
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        var location = 0
        var lines: [CTLine] = []
        while location < attributed.length, lines.count < maxLines {
            let count = CTTypesetterSuggestLineBreak(typesetter, location, Double(maxWidth))
            guard count > 0 else { break }
            lines.append(CTTypesetterCreateLine(
                typesetter,
                CFRange(location: location, length: count)
            ))
            location += count
        }

        let firstBaseline = centerY + CGFloat(lines.count - 1) * lineHeight / 2 - fontSize * 0.34
        for (index, line) in lines.enumerated() {
            draw(
                line: line,
                baselineY: firstBaseline - CGFloat(index) * lineHeight,
                in: context
            )
        }
    }

    private func drawCenteredLine(
        _ text: String,
        fontSize: CGFloat,
        emphasized: Bool,
        color: CGColor,
        baselineY: CGFloat,
        in context: CGContext
    ) {
        let font = systemFont(size: fontSize, emphasized: emphasized)
        let line = CTLineCreateWithAttributedString(NSAttributedString(
            string: text,
            attributes: attributes(font: font, color: color)
        ))
        draw(line: line, baselineY: baselineY, in: context)
    }

    private func draw(line: CTLine, baselineY: CGFloat, in context: CGContext) {
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        context.textPosition = CGPoint(x: max(48, (canvasWidth - width) / 2), y: baselineY)
        CTLineDraw(line, context)
    }

    private func attributes(font: CTFont, color: CGColor) -> [NSAttributedString.Key: Any] {
        [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
    }

    private func systemFont(size: CGFloat, emphasized: Bool) -> CTFont {
        CTFontCreateUIFontForLanguage(
            emphasized ? .emphasizedSystem : .system,
            size,
            nil
        ) ?? CTFontCreateWithName("Helvetica Neue" as CFString, size, nil)
    }

    private func expirationText(for date: Date?) -> String {
        guard let date else { return String(localized: "No expiration date") }
        return String(localized: "Valid until \(date.formatted(date: .long, time: .omitted))")
    }

    private func aspectFillRect(for image: CGImage, inside rect: CGRect) -> CGRect {
        let imageRatio = CGFloat(image.width) / CGFloat(image.height)
        let rectRatio = rect.width / rect.height
        if imageRatio > rectRatio {
            let width = rect.height * imageRatio
            return CGRect(x: rect.midX - width / 2, y: rect.minY, width: width, height: rect.height)
        }
        let height = rect.width / imageRatio
        return CGRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height)
    }
}
