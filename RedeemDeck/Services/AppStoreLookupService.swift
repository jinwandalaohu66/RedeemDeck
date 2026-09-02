import Foundation

nonisolated struct AppStoreMetadata: Sendable {
    let name: String
    let bundleID: String
    let artworkURL: String?
    let appStoreURL: String?
}

nonisolated enum AppStoreLookupError: LocalizedError, Sendable {
    case invalidAppID
    case appNotFound
    case connectionFailed
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidAppID:
            String(localized: "Enter a valid numeric App Store ID.")
        case .appNotFound:
            String(localized: "No app was found for this App Store ID.")
        case .connectionFailed:
            String(localized: "The App Store could not be reached. Check your connection and try again.")
        case .invalidResponse:
            String(localized: "The App Store returned data that could not be read.")
        }
    }
}

actor AppStoreLookupService {
    static let shared = AppStoreLookupService()

    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        session = URLSession(configuration: configuration)
    }

    func lookupApp(byID rawID: String) async throws -> AppStoreMetadata {
        let appID = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !appID.isEmpty, appID.allSatisfy(\.isNumber) else {
            throw AppStoreLookupError.invalidAppID
        }
        var components = URLComponents(string: "https://itunes.apple.com/lookup")
        components?.queryItems = [URLQueryItem(name: "id", value: appID)]
        guard let url = components?.url else {
            throw AppStoreLookupError.invalidAppID
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw AppStoreLookupError.connectionFailed
        }
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AppStoreLookupError.invalidResponse
        }

        let payload: LookupResponse
        do {
            payload = try JSONDecoder().decode(LookupResponse.self, from: data)
        } catch {
            throw AppStoreLookupError.invalidResponse
        }
        guard let result = payload.results.first else {
            throw AppStoreLookupError.appNotFound
        }
        return AppStoreMetadata(
            name: result.trackName,
            bundleID: result.bundleID,
            artworkURL: result.artworkURL,
            appStoreURL: result.trackViewURL
        )
    }
}

private nonisolated struct LookupResponse: Decodable {
    let results: [LookupResult]
}

private nonisolated struct LookupResult: Decodable {
    let trackName: String
    let bundleID: String
    let artworkURL: String?
    let trackViewURL: String?

    enum CodingKeys: String, CodingKey {
        case trackName
        case bundleID = "bundleId"
        case artworkURL = "artworkUrl100"
        case trackViewURL = "trackViewUrl"
    }
}
