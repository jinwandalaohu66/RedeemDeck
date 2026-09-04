import Foundation

enum RedeemDeckLinks {
    static let sourceCode = URL(string: "https://github.com/jinwandalaohu66/RedeemDeck")!
    static let license = URL(string: "https://github.com/jinwandalaohu66/RedeemDeck/blob/main/LICENSE")!
    static let privacyPolicy = URL(string: "https://github.com/jinwandalaohu66/RedeemDeck/blob/main/PRIVACY.md")!
    static let support = URL(string: "https://github.com/jinwandalaohu66/RedeemDeck/issues")!

    static var versionDescription: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (version, build) {
        case let (.some(version), .some(build)):
            return "\(version) (\(build))"
        case let (.some(version), .none):
            return version
        default:
            return "—"
        }
    }
}
