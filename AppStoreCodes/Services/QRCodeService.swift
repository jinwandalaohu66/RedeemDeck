import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum QRCodeGenerationError: Error, Sendable {
    case invalidValue
    case qrFilterOutputUnavailable
    case qrContextRenderingFailed
    case compositionFailed
    case pngEncodingFailed
}

nonisolated struct QRPosterContent: Hashable, Sendable {
    let redemptionURL: String
    let appName: String
    let expirationDate: Date?
    let greeting: String
    let iconURL: String?
}

nonisolated struct GeneratedQRPoster: @unchecked Sendable {
    let pngData: Data
    let image: CGImage
}

actor QRCodeService {
    static let shared = QRCodeService()

    static let posterWidth = 1_200
    static let posterHeight = 1_600

    private let context = CIContext(options: [
        .cacheIntermediates: false,
        .useSoftwareRenderer: true,
    ])
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 10
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: configuration)
    }

    func makePosterPNGData(from content: QRPosterContent) async throws -> Data {
        try await makePoster(from: content).pngData
    }

    func makePosterPNGData(
        contents: [QRPosterContent]
    ) async throws -> [Data] {
        guard !contents.isEmpty else {
            throw QRCodeGenerationError.invalidValue
        }
        let icon = await loadIcon(from: contents.first?.iconURL)
        var output: [Data] = []
        output.reserveCapacity(contents.count)
        for content in contents {
            try Task.checkCancellation()
            output.append(try render(content: content, icon: icon).pngData)
        }
        return output
    }

    func makePoster(from content: QRPosterContent) async throws -> GeneratedQRPoster {
        guard !content.redemptionURL.isEmpty else {
            throw QRCodeGenerationError.invalidValue
        }
        async let icon = loadIcon(from: content.iconURL)
        return try render(content: content, icon: await icon)
    }

    private func render(
        content: QRPosterContent,
        icon: CGImage?
    ) throws -> GeneratedQRPoster {
        let qrImage = try makeQRCode(from: content.redemptionURL)
        try Task.checkCancellation()
        let renderer = QRPosterRenderer()
        guard let artwork = renderer.render(qrImage: qrImage, icon: icon, content: content) else {
            throw QRCodeGenerationError.compositionFailed
        }
        guard let data = encodePNG(artwork) else {
            throw QRCodeGenerationError.pngEncodingFailed
        }
        return GeneratedQRPoster(pngData: data, image: artwork)
    }

    private func makeQRCode(from value: String) throws -> CGImage {
        guard !value.isEmpty else { throw QRCodeGenerationError.invalidValue }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "H"
        guard let output = filter.outputImage else {
            throw QRCodeGenerationError.qrFilterOutputUnavailable
        }
        guard let image = context.createCGImage(output, from: output.extent.integral) else {
            throw QRCodeGenerationError.qrContextRenderingFailed
        }
        return image
    }

    private func loadIcon(from urlString: String?) async -> CGImage? {
        guard let urlString,
              let url = URL(string: urlString),
              url.scheme?.lowercased() == "https" else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode),
                  data.count <= 5 * 1_024 * 1_024,
                  let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                return nil
            }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        } catch {
            return nil
        }
    }

    private func encodePNG(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
