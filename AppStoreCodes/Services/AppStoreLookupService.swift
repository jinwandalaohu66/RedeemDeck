//
//  AppStoreLookupService.swift
//  AppStoreCodes
//
//  Created by Matteo Comisso on 08/12/2025.
//

import Foundation

// MARK: - iTunes Lookup Response Models

struct iTunesLookupResponse: Decodable {
    let resultCount: Int
    let results: [iTunesAppResult]
}

struct iTunesAppResult: Decodable {
    let trackId: Int
    let trackName: String
    let bundleId: String
    let artworkUrl60: String?
    let artworkUrl100: String?
    let artworkUrl512: String?
    let trackViewUrl: String?
    let sellerName: String?
    let description: String?
    let version: String?
    let releaseDate: String?
    let currentVersionReleaseDate: String?
    let primaryGenreName: String?
    let price: Double?
    let currency: String?
    let formattedPrice: String?
    let averageUserRating: Double?
    let userRatingCount: Int?
    let fileSizeBytes: String?
    let minimumOsVersion: String?
    let supportedDevices: [String]?
    let screenshotUrls: [String]?
    let ipadScreenshotUrls: [String]?
    let releaseNotes: String?
}

// MARK: - App Metadata

struct AppMetadata: Sendable {
    let appStoreId: String
    let name: String
    let bundleId: String
    let iconURL: String?
    let appStoreURL: String?
    let developerName: String?
    let description: String?
    let version: String?
    let releaseDate: Date?
    let primaryGenre: String?
    let price: String?
    let currency: String?
}

// MARK: - Lookup Errors

enum AppStoreLookupError: LocalizedError {
    case invalidAppId
    case networkError(Error)
    case appNotFound
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidAppId:
            return "Invalid App Store ID"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .appNotFound:
            return "App not found on the App Store"
        case .invalidResponse:
            return "Invalid response from App Store"
        }
    }
}

// MARK: - App Store Lookup Service

final class AppStoreLookupService: Sendable {
    static let shared = AppStoreLookupService()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }

    /// Lookup app metadata by App Store ID
    /// - Parameter appStoreId: The numeric App Store ID (e.g., "1547173908")
    /// - Returns: App metadata
    func lookupApp(byId appStoreId: String) async throws -> AppMetadata {
        // Validate app ID is numeric
        guard Int(appStoreId) != nil else {
            throw AppStoreLookupError.invalidAppId
        }

        // iTunes Lookup API
        let urlString = "https://itunes.apple.com/lookup?id=\(appStoreId)"
        guard let url = URL(string: urlString) else {
            throw AppStoreLookupError.invalidAppId
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AppStoreLookupError.invalidResponse
        }

        let decoder = JSONDecoder()
        let lookupResponse = try decoder.decode(iTunesLookupResponse.self, from: data)

        guard let result = lookupResponse.results.first else {
            throw AppStoreLookupError.appNotFound
        }

        // Parse release date
        var releaseDate: Date? = nil
        if let dateString = result.releaseDate {
            let formatter = ISO8601DateFormatter()
            releaseDate = formatter.date(from: dateString)
        }

        // Format price
        var priceString: String? = nil
        if let price = result.price {
            if price == 0 {
                priceString = "Free"
            } else {
                priceString = result.formattedPrice ?? String(format: "%.2f", price)
            }
        }

        return AppMetadata(
            appStoreId: appStoreId,
            name: result.trackName,
            bundleId: result.bundleId,
            iconURL: result.artworkUrl512 ?? result.artworkUrl100 ?? result.artworkUrl60,
            appStoreURL: result.trackViewUrl,
            developerName: result.sellerName,
            description: result.description,
            version: result.version,
            releaseDate: releaseDate,
            primaryGenre: result.primaryGenreName,
            price: priceString,
            currency: result.currency
        )
    }

    /// Lookup multiple apps by their IDs
    /// - Parameter appStoreIds: Array of App Store IDs
    /// - Returns: Dictionary of app ID to metadata (nil if not found)
    func lookupApps(byIds appStoreIds: [String]) async -> [String: AppMetadata?] {
        await withTaskGroup(of: (String, AppMetadata?).self) { group in
            for appId in appStoreIds {
                group.addTask {
                    let metadata = try? await self.lookupApp(byId: appId)
                    return (appId, metadata)
                }
            }

            var results: [String: AppMetadata?] = [:]
            for await (appId, metadata) in group {
                results[appId] = metadata
            }
            return results
        }
    }

    /// Update an AppRecord with metadata from the App Store
    /// - Parameter app: The AppRecord to update
    @MainActor
    func updateAppRecord(_ app: AppRecord) async throws {
        let metadata = try await lookupApp(byId: app.appStoreId)

        app.name = metadata.name
        app.bundleId = metadata.bundleId
        app.iconURL = metadata.iconURL
        app.appStoreURL = metadata.appStoreURL
        app.developerName = metadata.developerName
        app.appDescription = metadata.description
        app.version = metadata.version
        app.releaseDate = metadata.releaseDate
        app.primaryGenre = metadata.primaryGenre
        app.price = metadata.price
        app.currency = metadata.currency
        app.metadataLastUpdated = Date()
    }
}
