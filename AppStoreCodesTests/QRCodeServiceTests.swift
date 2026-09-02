import Foundation
import ImageIO
import Testing
import Vision
@testable import CodeVault

struct QRCodeServiceTests {
    @Test("Redemption poster is a portrait PNG")
    func generatesExportSizedPNG() async throws {
        let data = try await QRCodeService.shared.makePosterPNGData(from: QRPosterContent(
            redemptionURL: "https://apps.apple.com/redeem?code=TEST-CODE",
            appName: "Example",
            expirationDate: Date(timeIntervalSince1970: 2_000_000_000),
            greeting: "Enjoy your gift!",
            iconURL: nil
        ))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try #require(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )

        #expect(properties[kCGImagePropertyPixelWidth] as? Int == QRCodeService.posterWidth)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == QRCodeService.posterHeight)
    }

    @Test("Empty QR values are rejected")
    func rejectsEmptyValue() async {
        await #expect(throws: QRCodeGenerationError.self) {
            _ = try await QRCodeService.shared.makePosterPNGData(from: QRPosterContent(
                redemptionURL: "",
                appName: "Example",
                expirationDate: nil,
                greeting: "Enjoy!",
                iconURL: nil
            ))
        }
    }

    @Test("Rounded poster QR remains scannable")
    func roundedPosterRemainsScannable() async throws {
        let redemptionURL = "https://apps.apple.com/redeem?code=ROUND-TEST-CODE"
        let data = try await QRCodeService.shared.makePosterPNGData(from: QRPosterContent(
            redemptionURL: redemptionURL,
            appName: "Example",
            expirationDate: Date(timeIntervalSince1970: 2_000_000_000),
            greeting: "Enjoy your gift!",
            iconURL: nil
        ))
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]

        try VNImageRequestHandler(data: data).perform([request])

        #expect(request.results?.contains {
            $0.payloadStringValue == redemptionURL
        } == true)
    }
}
