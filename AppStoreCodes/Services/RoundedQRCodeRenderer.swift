import CoreGraphics

nonisolated struct RoundedQRCodeRenderer {
    func draw(_ image: CGImage, in rect: CGRect, context: CGContext) -> Bool {
        guard let modules = moduleMatrix(from: image) else { return false }
        drawModules(modules, count: image.width, in: rect, context: context)
        return true
    }

    private func moduleMatrix(from image: CGImage) -> [Bool]? {
        let count = image.width
        guard count > 0, image.height == count else { return nil }
        var pixels = [UInt8](repeating: 255, count: count * count)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: count,
                height: count,
                bitsPerComponent: 8,
                bytesPerRow: count,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: count, height: count))
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: count, height: count))
            return true
        }
        return rendered ? pixels.map { $0 < 128 } : nil
    }

    private func drawModules(
        _ modules: [Bool],
        count: Int,
        in rect: CGRect,
        context: CGContext
    ) {
        let module = rect.width / CGFloat(count)
        let finders = finderOrigins(in: modules, count: count)
        context.setFillColor(CGColor(gray: 0.02, alpha: 1))

        for row in 0..<count {
            for column in 0..<count where modules[row * count + column] {
                guard !finders.contains(where: {
                    column >= $0.x && column < $0.x + 7
                        && row >= $0.y && row < $0.y + 7
                }) else { continue }
                let cell = CGRect(
                    x: rect.minX + CGFloat(column) * module,
                    y: rect.minY + CGFloat(row) * module,
                    width: module,
                    height: module
                ).insetBy(dx: module * 0.055, dy: module * 0.055)
                context.addPath(CGPath(
                    roundedRect: cell,
                    cornerWidth: module * 0.28,
                    cornerHeight: module * 0.28,
                    transform: nil
                ))
                context.fillPath()
            }
        }
        for origin in finders {
            drawFinder(origin: origin, module: module, in: rect, context: context)
        }
    }

    private func finderOrigins(in modules: [Bool], count: Int) -> [(x: Int, y: Int)] {
        guard count >= 7 else { return [] }
        let edgeAllowance = min(6, max(1, count / 6))
        var origins: [(x: Int, y: Int)] = []
        for y in 0...(count - 7) {
            for x in 0...(count - 7) {
                let nearHorizontalEdge = x <= edgeAllowance
                    || x >= count - 7 - edgeAllowance
                let nearVerticalEdge = y <= edgeAllowance
                    || y >= count - 7 - edgeAllowance
                guard nearHorizontalEdge, nearVerticalEdge else { continue }
                if matchesFinder(atX: x, y: y, modules: modules, count: count) {
                    origins.append((x, y))
                }
            }
        }
        return origins
    }

    private func matchesFinder(
        atX x: Int,
        y: Int,
        modules: [Bool],
        count: Int
    ) -> Bool {
        for row in 0..<7 {
            for column in 0..<7 {
                let isOuterRing = row == 0 || row == 6 || column == 0 || column == 6
                let isCenter = (2...4).contains(row) && (2...4).contains(column)
                if modules[(y + row) * count + x + column] != (isOuterRing || isCenter) {
                    return false
                }
            }
        }
        return true
    }

    private func drawFinder(
        origin: (x: Int, y: Int),
        module: CGFloat,
        in qrRect: CGRect,
        context: CGContext
    ) {
        let outer = CGRect(
            x: qrRect.minX + CGFloat(origin.x) * module,
            y: qrRect.minY + CGFloat(origin.y) * module,
            width: module * 7,
            height: module * 7
        )
        fillRounded(outer, radius: module * 1.55, gray: 0.02, in: context)
        fillRounded(outer.insetBy(dx: module, dy: module), radius: module, gray: 1, in: context)
        fillRounded(
            outer.insetBy(dx: module * 2, dy: module * 2),
            radius: module * 0.72,
            gray: 0.02,
            in: context
        )
    }

    private func fillRounded(
        _ rect: CGRect,
        radius: CGFloat,
        gray: CGFloat,
        in context: CGContext
    ) {
        context.addPath(CGPath(
            roundedRect: rect,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        ))
        context.setFillColor(CGColor(gray: gray, alpha: 1))
        context.fillPath()
    }
}
