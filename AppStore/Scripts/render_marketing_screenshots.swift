#!/usr/bin/env swift

import AppKit
import Foundation

private struct MarketingCopy {
    let title: String
    let subtitle: String
}

private struct Shot {
    let number: String
    let stem: String
    let english: MarketingCopy
    let chinese: MarketingCopy
}

private struct DeviceLayout {
    let slug: String
    let canvas: CGSize
    let screenshotWidth: CGFloat
    let screenshotTop: CGFloat
    let framePadding: CGFloat
    let frameRadius: CGFloat
    let screenRadius: CGFloat
    let titleTop: CGFloat
    let titleSize: CGFloat
    let subtitleTop: CGFloat
    let subtitleSize: CGFloat
}

private let shots = [
    Shot(
        number: "01",
        stem: "library",
        english: MarketingCopy(
            title: "Every offer code. One clean library.",
            subtitle: "Organize apps, offers, and inventory at a glance"
        ),
        chinese: MarketingCopy(
            title: "所有兑换码，一处清晰管理",
            subtitle: "按 App 与优惠类型整理，库存一目了然"
        )
    ),
    Shot(
        number: "02",
        stem: "quantity",
        english: MarketingCopy(
            title: "Get exactly what you need",
            subtitle: "Choose a quantity and offer—nothing else"
        ),
        chinese: MarketingCopy(
            title: "要几个，就获取几个",
            subtitle: "选择数量和优惠类型，立即完成"
        )
    ),
    Shot(
        number: "03",
        stem: "codes",
        english: MarketingCopy(
            title: "Copy codes in a tap",
            subtitle: "Full codes, clear status, instant feedback"
        ),
        chinese: MarketingCopy(
            title: "兑换码，一点即复制",
            subtitle: "完整显示，状态清晰，操作即时反馈"
        )
    ),
    Shot(
        number: "04",
        stem: "links",
        english: MarketingCopy(
            title: "Share ready-to-redeem links",
            subtitle: "Copy one link or the entire selection"
        ),
        chinese: MarketingCopy(
            title: "兑换链接，拿来就能分享",
            subtitle: "逐条复制，也可一次处理全部"
        )
    ),
    Shot(
        number: "05",
        stem: "posters",
        english: MarketingCopy(
            title: "Turn every code into a gift",
            subtitle: "Polished QR posters with artwork and expiry"
        ),
        chinese: MarketingCopy(
            title: "把每个兑换码变成一份礼物",
            subtitle: "App 图标、到期时间与祝福语都在其中"
        )
    ),
    Shot(
        number: "06",
        stem: "open-source",
        english: MarketingCopy(
            title: "Local by design. Open by choice.",
            subtitle: "No account, no tracking, fully open source"
        ),
        chinese: MarketingCopy(
            title: "本地优先，也完全开源",
            subtitle: "无需账号，不跟踪，源码公开"
        )
    ),
]

private let layouts = [
    DeviceLayout(
        slug: "iPhone-6.9",
        canvas: CGSize(width: 1320, height: 2868),
        screenshotWidth: 1050,
        screenshotTop: 390,
        framePadding: 18,
        frameRadius: 82,
        screenRadius: 66,
        titleTop: 82,
        titleSize: 76,
        subtitleTop: 222,
        subtitleSize: 37
    ),
    DeviceLayout(
        slug: "iPad-13",
        canvas: CGSize(width: 2064, height: 2752),
        screenshotWidth: 1640,
        screenshotTop: 402,
        framePadding: 22,
        frameRadius: 76,
        screenRadius: 54,
        titleTop: 76,
        titleSize: 88,
        subtitleTop: 228,
        subtitleSize: 43
    ),
]

guard CommandLine.arguments.count == 2 else {
    fputs("usage: render_marketing_screenshots.swift REPOSITORY_ROOT\n", stderr)
    exit(2)
}

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let fileManager = FileManager.default

for layout in layouts {
    for locale in ["en-US", "zh-Hans"] {
        let suffix = locale == "en-US" ? "en" : "zh-Hans"
        let sourceDirectory = root
            .appendingPathComponent("AppStore/Screenshots/Source", isDirectory: true)
            .appendingPathComponent(layout.slug, isDirectory: true)
            .appendingPathComponent(locale, isDirectory: true)
        let outputDirectory = root
            .appendingPathComponent("AppStore/Screenshots/Marketing", isDirectory: true)
            .appendingPathComponent(layout.slug, isDirectory: true)
            .appendingPathComponent(locale, isDirectory: true)
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        for shot in shots {
            let filename = "\(shot.number)-\(shot.stem)-\(suffix).png"
            let source = sourceDirectory.appendingPathComponent(filename)
            let destination = outputDirectory.appendingPathComponent(filename)
            let copy = locale == "en-US" ? shot.english : shot.chinese
            try render(source: source, destination: destination, copy: copy, layout: layout)
            print("rendered \(destination.path)")
        }
    }
}

private func render(
    source: URL,
    destination: URL,
    copy: MarketingCopy,
    layout: DeviceLayout
) throws {
    guard let screenshot = NSImage(contentsOf: source) else {
        throw NSError(
            domain: "RedeemDeckMarketing",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unable to load \(source.path)"]
        )
    }

    let width = Int(layout.canvas.width)
    let height = Int(layout.canvas.height)
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "RedeemDeckMarketing", code: 2)
    }

    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        NSGraphicsContext.restoreGraphicsState()
        throw NSError(domain: "RedeemDeckMarketing", code: 3)
    }
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    drawBackground(canvas: layout.canvas)
    drawCopy(copy, layout: layout)
    drawDevice(screenshot, layout: layout)

    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [.compressionFactor: 0.92]) else {
        throw NSError(domain: "RedeemDeckMarketing", code: 4)
    }
    try writeOpaquePNG(data, destination: destination)
}

private func writeOpaquePNG(_ data: Data, destination: URL) throws {
    let temporary = destination
        .deletingLastPathComponent()
        .appendingPathComponent(".\(destination.lastPathComponent).rgba.png")
    try data.write(to: temporary, options: .atomic)
    defer { try? FileManager.default.removeItem(at: temporary) }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [
        "magick",
        temporary.path,
        "-background", "#000000",
        "-alpha", "remove",
        "-alpha", "off",
        "-depth", "8",
        "PNG24:\(destination.path)",
    ]
    let errorPipe = Pipe()
    process.standardError = errorPipe
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let error = String(
            data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? "ImageMagick failed"
        throw NSError(
            domain: "RedeemDeckMarketing",
            code: 5,
            userInfo: [NSLocalizedDescriptionKey: error]
        )
    }
}

private func drawBackground(canvas: CGSize) {
    let bounds = NSRect(origin: .zero, size: canvas)
    let gradient = NSGradient(
        starting: NSColor(calibratedRed: 0.40, green: 0.51, blue: 0.64, alpha: 1),
        ending: NSColor(calibratedRed: 0.24, green: 0.33, blue: 0.44, alpha: 1)
    )!
    gradient.draw(in: bounds, angle: 90)

    let cobaltGlow = NSBezierPath(ovalIn: NSRect(
        x: canvas.width * 0.54,
        y: canvas.height * 0.52,
        width: canvas.width * 0.72,
        height: canvas.width * 0.72
    ))
    NSColor(calibratedRed: 0.12, green: 0.35, blue: 0.88, alpha: 0.13).setFill()
    cobaltGlow.fill()

    let iceGlow = NSBezierPath(ovalIn: NSRect(
        x: -canvas.width * 0.32,
        y: canvas.height * 0.62,
        width: canvas.width * 0.82,
        height: canvas.width * 0.82
    ))
    NSColor(calibratedRed: 0.48, green: 0.82, blue: 1.0, alpha: 0.08).setFill()
    iceGlow.fill()
}

private func drawCopy(_ copy: MarketingCopy, layout: DeviceLayout) {
    let horizontalMargin = layout.canvas.width * 0.07
    let maxWidth = layout.canvas.width - horizontalMargin * 2

    let titleFont = fittedFont(
        text: copy.title,
        startingSize: layout.titleSize,
        minimumSize: layout.titleSize * 0.64,
        weight: .bold,
        maxWidth: maxWidth
    )
    drawCentered(
        copy.title,
        top: layout.titleTop,
        height: titleFont.pointSize * 1.32,
        canvas: layout.canvas,
        font: titleFont,
        color: .white
    )

    let subtitleFont = fittedFont(
        text: copy.subtitle,
        startingSize: layout.subtitleSize,
        minimumSize: layout.subtitleSize * 0.72,
        weight: .medium,
        maxWidth: maxWidth
    )
    drawCentered(
        copy.subtitle,
        top: layout.subtitleTop,
        height: subtitleFont.pointSize * 1.42,
        canvas: layout.canvas,
        font: subtitleFont,
        color: NSColor.white.withAlphaComponent(0.86)
    )
}

private func drawDevice(_ screenshot: NSImage, layout: DeviceLayout) {
    let sourceSize = screenshot.size
    let screenshotHeight = layout.screenshotWidth * sourceSize.height / sourceSize.width
    let screenRect = topRect(
        x: (layout.canvas.width - layout.screenshotWidth) / 2,
        top: layout.screenshotTop,
        width: layout.screenshotWidth,
        height: screenshotHeight,
        canvasHeight: layout.canvas.height
    )
    let frameRect = screenRect.insetBy(dx: -layout.framePadding, dy: -layout.framePadding)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.34)
    shadow.shadowBlurRadius = layout.canvas.width * 0.026
    shadow.shadowOffset = NSSize(width: 0, height: -layout.canvas.width * 0.012)
    shadow.set()
    NSColor(calibratedWhite: 0.055, alpha: 1).setFill()
    NSBezierPath(roundedRect: frameRect, xRadius: layout.frameRadius, yRadius: layout.frameRadius).fill()
    NSGraphicsContext.restoreGraphicsState()

    NSColor.white.withAlphaComponent(0.13).setStroke()
    let border = NSBezierPath(roundedRect: frameRect, xRadius: layout.frameRadius, yRadius: layout.frameRadius)
    border.lineWidth = max(2, layout.canvas.width * 0.0016)
    border.stroke()

    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(
        roundedRect: screenRect,
        xRadius: layout.screenRadius,
        yRadius: layout.screenRadius
    ).addClip()
    screenshot.draw(
        in: screenRect,
        from: NSRect(origin: .zero, size: sourceSize),
        operation: .copy,
        fraction: 1,
        respectFlipped: true,
        hints: [.interpolation: NSImageInterpolation.high]
    )
    NSGraphicsContext.restoreGraphicsState()
}

private func fittedFont(
    text: String,
    startingSize: CGFloat,
    minimumSize: CGFloat,
    weight: NSFont.Weight,
    maxWidth: CGFloat
) -> NSFont {
    var size = startingSize
    while size > minimumSize {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        let width = (text as NSString).size(withAttributes: [.font: font]).width
        if width <= maxWidth {
            return font
        }
        size -= 1
    }
    return NSFont.systemFont(ofSize: minimumSize, weight: weight)
}

private func drawCentered(
    _ text: String,
    top: CGFloat,
    height: CGFloat,
    canvas: CGSize,
    font: NSFont,
    color: NSColor
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineBreakMode = .byClipping
    let rect = topRect(
        x: 0,
        top: top,
        width: canvas.width,
        height: height,
        canvasHeight: canvas.height
    )
    (text as NSString).draw(
        in: rect,
        withAttributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
    )
}

private func topRect(
    x: CGFloat,
    top: CGFloat,
    width: CGFloat,
    height: CGFloat,
    canvasHeight: CGFloat
) -> NSRect {
    NSRect(x: x, y: canvasHeight - top - height, width: width, height: height)
}
