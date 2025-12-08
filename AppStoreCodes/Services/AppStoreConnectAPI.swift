//
//  AppStoreConnectAPI.swift
//  AppStoreCodes
//
//  Created by Matteo Comisso on 08/12/2025.
//

import Foundation
import Combine

// MARK: - API Errors

enum AppStoreConnectError: LocalizedError {
    case notConfigured
    case invalidCredentials
    case networkError(Error)
    case invalidResponse
    case apiError(String)
    case rateLimited
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "API credentials not configured. Please set up your API key in Settings."
        case .invalidCredentials:
            return "Invalid API credentials. Please check your Key ID, Issuer ID, and API key."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from App Store Connect API."
        case .apiError(let message):
            return "API error: \(message)"
        case .rateLimited:
            return "Rate limited. Please wait before making more requests."
        case .unauthorized:
            return "Unauthorized. Please check your API credentials."
        }
    }
}

// MARK: - API Response Models

struct APIResponse<T: Decodable>: Decodable {
    let data: T
    let links: APILinks?
    let meta: APIMeta?
}

struct APIListResponse<T: Decodable>: Decodable {
    let data: [T]
    let links: APILinks?
    let meta: APIMeta?
    let included: [APIIncluded]?
}

struct APILinks: Decodable {
    let `self`: String?
    let next: String?
    let first: String?
}

struct APIMeta: Decodable {
    let paging: APIPaging?
}

struct APIPaging: Decodable {
    let total: Int?
    let limit: Int?
}

struct APIIncluded: Decodable {
    let type: String
    let id: String
    let attributes: APIIncludedAttributes?
}

struct APIIncludedAttributes: Decodable {
    let name: String?
}

struct APIErrorResponse: Decodable {
    let errors: [APIErrorDetail]
}

struct APIErrorDetail: Decodable {
    let status: String
    let code: String
    let title: String
    let detail: String?
}

// MARK: - App Models

struct APIApp: Decodable, Identifiable, Hashable, Sendable {
    let type: String
    let id: String
    let attributes: APIAppAttributes

    struct APIAppAttributes: Decodable, Hashable, Sendable {
        let name: String
        let bundleId: String
    }

    static func == (lhs: APIApp, rhs: APIApp) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Subscription Models

struct APISubscription: Decodable, Identifiable, Hashable, Sendable {
    let type: String
    let id: String
    let attributes: APISubscriptionAttributes

    struct APISubscriptionAttributes: Decodable, Hashable, Sendable {
        let name: String
        let productId: String
        let state: String
    }

    static func == (lhs: APISubscription, rhs: APISubscription) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct APISubscriptionGroup: Decodable, Identifiable, Hashable, Sendable {
    let type: String
    let id: String
    let attributes: APISubscriptionGroupAttributes

    struct APISubscriptionGroupAttributes: Decodable, Hashable, Sendable {
        let referenceName: String
    }

    static func == (lhs: APISubscriptionGroup, rhs: APISubscriptionGroup) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Offer Code Models

struct APISubscriptionOfferCode: Decodable, Identifiable, Hashable, Sendable {
    let type: String
    let id: String
    let attributes: APISubscriptionOfferCodeAttributes

    struct APISubscriptionOfferCodeAttributes: Decodable, Hashable, Sendable {
        let name: String
        let numberOfPeriods: Int
        let offerEligibility: String
        let offerMode: String
        let active: Bool
    }

    static func == (lhs: APISubscriptionOfferCode, rhs: APISubscriptionOfferCode) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct APIOneTimeUseCode: Decodable, Identifiable, Hashable, Sendable {
    let type: String
    let id: String
    let attributes: APIOneTimeUseCodeAttributes

    struct APIOneTimeUseCodeAttributes: Decodable, Hashable, Sendable {
        let numberOfCodes: Int
        let createdDate: String
        let expirationDate: String?
        let active: Bool
    }

    static func == (lhs: APIOneTimeUseCode, rhs: APIOneTimeUseCode) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Offer Code Pricing Models

struct APISubscriptionOfferCodePrice: Decodable, Identifiable, Hashable, Sendable {
    let type: String
    let id: String
    let relationships: APIOfferCodePriceRelationships?

    struct APIOfferCodePriceRelationships: Decodable, Hashable, Sendable {
        let territory: APIRelationshipData?
        let subscriptionPricePoint: APIRelationshipData?
    }

    struct APIRelationshipData: Decodable, Hashable, Sendable {
        let data: APIResourceIdentifier?
    }

    struct APIResourceIdentifier: Decodable, Hashable, Sendable {
        let type: String
        let id: String
    }

    static func == (lhs: APISubscriptionOfferCodePrice, rhs: APISubscriptionOfferCodePrice) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct APITerritory: Decodable, Identifiable, Hashable, Sendable {
    let type: String
    let id: String
    let attributes: APITerritoryAttributes?

    struct APITerritoryAttributes: Decodable, Hashable, Sendable {
        let currency: String?
    }

    static func == (lhs: APITerritory, rhs: APITerritory) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct APISubscriptionPricePoint: Decodable, Identifiable, Hashable, Sendable {
    let type: String
    let id: String
    let attributes: APISubscriptionPricePointAttributes?

    struct APISubscriptionPricePointAttributes: Decodable, Hashable, Sendable {
        let customerPrice: String?
        let proceeds: String?
    }

    static func == (lhs: APISubscriptionPricePoint, rhs: APISubscriptionPricePoint) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Parsed offer code pricing info
struct OfferCodePricing: Sendable {
    let territory: String
    let currency: String
    let customerPrice: String
}

/// Special response for offer code prices with polymorphic included array
struct APIOfferCodePricesResponse: Decodable {
    let data: [APISubscriptionOfferCodePrice]
    let included: [APIIncludedPriceData]?
    let links: APILinks?
}

/// Polymorphic included data for pricing response
struct APIIncludedPriceData: Decodable {
    let type: String
    let id: String
    let territoryAttributes: TerritoryAttrs?
    let pricePointAttributes: PricePointAttrs?

    struct TerritoryAttrs: Decodable {
        let currency: String?
    }

    struct PricePointAttrs: Decodable {
        let customerPrice: String?
        let proceeds: String?
    }

    enum CodingKeys: String, CodingKey {
        case type, id, attributes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        id = try container.decode(String.self, forKey: .id)

        if type == "territories" {
            territoryAttributes = try container.decodeIfPresent(TerritoryAttrs.self, forKey: .attributes)
            pricePointAttributes = nil
        } else if type == "subscriptionPricePoints" {
            pricePointAttributes = try container.decodeIfPresent(PricePointAttrs.self, forKey: .attributes)
            territoryAttributes = nil
        } else {
            territoryAttributes = nil
            pricePointAttributes = nil
        }
    }
}

// MARK: - API Client

@MainActor
final class AppStoreConnectAPI: ObservableObject {
    static let shared = AppStoreConnectAPI()

    private let baseURL = "https://api.appstoreconnect.apple.com/v1"
    private let session: URLSession

    @Published var isConfigured = false
    @Published var isLoading = false
    @Published var lastError: AppStoreConnectError?

    private var cachedToken: String?
    private var tokenExpiration: Date?

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
        checkConfiguration()
    }

    // MARK: - Configuration

    func checkConfiguration() {
        let keyId = UserDefaults.standard.string(forKey: "apiKeyId") ?? ""
        isConfigured = !keyId.isEmpty && KeychainService.shared.hasAPIKey(keyId: keyId)
    }

    private func getToken() throws -> String {
        // Return cached token if still valid
        if let token = cachedToken, let expiration = tokenExpiration, Date() < expiration {
            return token
        }

        // Get credentials
        guard let keyId = UserDefaults.standard.string(forKey: "apiKeyId"), !keyId.isEmpty else {
            throw AppStoreConnectError.notConfigured
        }

        let issuerId: String
        do {
            issuerId = try KeychainService.shared.getIssuerId()
        } catch {
            throw AppStoreConnectError.notConfigured
        }

        let privateKeyData: Data
        do {
            privateKeyData = try KeychainService.shared.getAPIKey(keyId: keyId)
        } catch {
            throw AppStoreConnectError.notConfigured
        }

        guard let privateKeyPEM = String(data: privateKeyData, encoding: .utf8) else {
            throw AppStoreConnectError.invalidCredentials
        }

        // Generate new token
        do {
            let generator = try JWTGenerator(keyId: keyId, issuerId: issuerId, privateKeyPEM: privateKeyPEM)
            let token = try generator.generateToken(expirationMinutes: 15)

            // Cache the token
            cachedToken = token
            tokenExpiration = Date().addingTimeInterval(14 * 60) // Expire 1 minute early

            return token
        } catch {
            throw AppStoreConnectError.invalidCredentials
        }
    }

    // MARK: - API Requests

    private func request<T: Decodable>(_ endpoint: String, type: T.Type) async throws -> T {
        let token = try getToken()

        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw AppStoreConnectError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppStoreConnectError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        case 401:
            cachedToken = nil
            throw AppStoreConnectError.unauthorized
        case 429:
            throw AppStoreConnectError.rateLimited
        default:
            if let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data),
               let firstError = errorResponse.errors.first {
                throw AppStoreConnectError.apiError(firstError.detail ?? firstError.title)
            }
            throw AppStoreConnectError.invalidResponse
        }
    }

    // MARK: - Fetch CSV Codes

    private func fetchCSV(_ endpoint: String) async throws -> String {
        let token = try getToken()

        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw AppStoreConnectError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("text/csv", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppStoreConnectError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            guard let csvString = String(data: data, encoding: .utf8) else {
                throw AppStoreConnectError.invalidResponse
            }
            return csvString
        case 401:
            cachedToken = nil
            throw AppStoreConnectError.unauthorized
        case 429:
            throw AppStoreConnectError.rateLimited
        default:
            throw AppStoreConnectError.apiError("Failed to fetch codes (HTTP \(httpResponse.statusCode))")
        }
    }

    // MARK: - Public API Methods

    /// Fetch all apps
    func fetchApps() async throws -> [APIApp] {
        isLoading = true
        defer { isLoading = false }

        let response: APIListResponse<APIApp> = try await request("/apps", type: APIListResponse<APIApp>.self)
        return response.data
    }

    /// Fetch subscription groups for an app
    func fetchSubscriptionGroups(appId: String) async throws -> [APISubscriptionGroup] {
        isLoading = true
        defer { isLoading = false }

        let response: APIListResponse<APISubscriptionGroup> = try await request(
            "/apps/\(appId)/subscriptionGroups",
            type: APIListResponse<APISubscriptionGroup>.self
        )
        return response.data
    }

    /// Fetch subscriptions for a subscription group
    func fetchSubscriptions(groupId: String) async throws -> [APISubscription] {
        isLoading = true
        defer { isLoading = false }

        let response: APIListResponse<APISubscription> = try await request(
            "/subscriptionGroups/\(groupId)/subscriptions",
            type: APIListResponse<APISubscription>.self
        )
        return response.data
    }

    /// Fetch offer codes for a subscription
    func fetchOfferCodes(subscriptionId: String) async throws -> [APISubscriptionOfferCode] {
        isLoading = true
        defer { isLoading = false }

        let response: APIListResponse<APISubscriptionOfferCode> = try await request(
            "/subscriptions/\(subscriptionId)/subscriptionOfferCodes?filter[active]=true",
            type: APIListResponse<APISubscriptionOfferCode>.self
        )
        return response.data
    }

    /// Fetch one-time use code batches for an offer code
    func fetchOneTimeUseCodes(offerCodeId: String) async throws -> [APIOneTimeUseCode] {
        isLoading = true
        defer { isLoading = false }

        let response: APIListResponse<APIOneTimeUseCode> = try await request(
            "/subscriptionOfferCodes/\(offerCodeId)/oneTimeUseCodes",
            type: APIListResponse<APIOneTimeUseCode>.self
        )
        return response.data
    }

    /// Fetch the actual code values (CSV) for a one-time use code batch
    func fetchCodeValues(oneTimeUseCodeId: String) async throws -> String {
        isLoading = true
        defer { isLoading = false }

        return try await fetchCSV("/subscriptionOfferCodeOneTimeUseCodes/\(oneTimeUseCodeId)/values")
    }

    /// Validate API credentials by making a test request
    func validateCredentials() async throws -> Bool {
        _ = try await fetchApps()
        return true
    }

    /// Fetch pricing for an offer code (with included territories and price points)
    func fetchOfferCodePricing(offerCodeId: String) async throws -> [OfferCodePricing] {
        isLoading = true
        defer { isLoading = false }

        // Request with includes to get territory and price point data
        let endpoint = "/subscriptionOfferCodes/\(offerCodeId)/prices?include=territory,subscriptionPricePoint&limit=200"
        let response: APIOfferCodePricesResponse = try await request(endpoint, type: APIOfferCodePricesResponse.self)

        // Build lookup dictionaries from included data
        var territories: [String: APITerritory] = [:]
        var pricePoints: [String: APISubscriptionPricePoint] = [:]

        for included in response.included ?? [] {
            if included.type == "territories", let attrs = included.territoryAttributes {
                territories[included.id] = APITerritory(
                    type: included.type,
                    id: included.id,
                    attributes: APITerritory.APITerritoryAttributes(currency: attrs.currency)
                )
            } else if included.type == "subscriptionPricePoints", let attrs = included.pricePointAttributes {
                pricePoints[included.id] = APISubscriptionPricePoint(
                    type: included.type,
                    id: included.id,
                    attributes: APISubscriptionPricePoint.APISubscriptionPricePointAttributes(
                        customerPrice: attrs.customerPrice,
                        proceeds: attrs.proceeds
                    )
                )
            }
        }

        // Map prices to OfferCodePricing objects
        var pricing: [OfferCodePricing] = []
        for price in response.data {
            guard let territoryId = price.relationships?.territory?.data?.id,
                  let pricePointId = price.relationships?.subscriptionPricePoint?.data?.id,
                  let territory = territories[territoryId],
                  let pricePoint = pricePoints[pricePointId] else {
                continue
            }

            pricing.append(OfferCodePricing(
                territory: territoryId,
                currency: territory.attributes?.currency ?? "USD",
                customerPrice: pricePoint.attributes?.customerPrice ?? "0.00"
            ))
        }

        return pricing
    }

    /// Deactivate an offer code (no new codes can be created or redeemed)
    /// - Parameter offerCodeId: The ID of the subscription offer code to deactivate
    func deactivateOfferCode(offerCodeId: String) async throws {
        isLoading = true
        defer { isLoading = false }

        let token = try getToken()

        guard let url = URL(string: "\(baseURL)/subscriptionOfferCodes/\(offerCodeId)") else {
            throw AppStoreConnectError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "data": [
                "type": "subscriptionOfferCodes",
                "id": offerCodeId,
                "attributes": [
                    "active": false
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppStoreConnectError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return // Success
        case 401:
            cachedToken = nil
            throw AppStoreConnectError.unauthorized
        case 429:
            throw AppStoreConnectError.rateLimited
        default:
            if let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data),
               let firstError = errorResponse.errors.first {
                throw AppStoreConnectError.apiError(firstError.detail ?? firstError.title)
            }
            throw AppStoreConnectError.apiError("Failed to deactivate offer code (HTTP \(httpResponse.statusCode))")
        }
    }

    // MARK: - Create Codes

    /// Create new one-time use codes for an offer
    /// - Parameters:
    ///   - offerCodeId: The ID of the subscription offer code
    ///   - numberOfCodes: Number of codes to create (1-500,000 per request)
    ///   - expirationDate: Optional expiration date (ISO 8601 format)
    /// - Returns: The created one-time use code batch
    func createOneTimeUseCodes(offerCodeId: String, numberOfCodes: Int, expirationDate: Date? = nil) async throws -> APIOneTimeUseCode {
        isLoading = true
        defer { isLoading = false }

        let token = try getToken()

        guard let url = URL(string: "\(baseURL)/subscriptionOfferCodeOneTimeUseCodes") else {
            throw AppStoreConnectError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build request body
        var attributes: [String: Any] = ["numberOfCodes": numberOfCodes]
        if let expirationDate = expirationDate {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            attributes["expirationDate"] = formatter.string(from: expirationDate)
        }

        let body: [String: Any] = [
            "data": [
                "type": "subscriptionOfferCodeOneTimeUseCodes",
                "attributes": attributes,
                "relationships": [
                    "offerCode": [
                        "data": [
                            "type": "subscriptionOfferCodes",
                            "id": offerCodeId
                        ]
                    ]
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppStoreConnectError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            let decoder = JSONDecoder()
            let apiResponse = try decoder.decode(APIResponse<APIOneTimeUseCode>.self, from: data)
            return apiResponse.data
        case 401:
            cachedToken = nil
            throw AppStoreConnectError.unauthorized
        case 429:
            throw AppStoreConnectError.rateLimited
        default:
            if let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data),
               let firstError = errorResponse.errors.first {
                throw AppStoreConnectError.apiError(firstError.detail ?? firstError.title)
            }
            throw AppStoreConnectError.apiError("Failed to create codes (HTTP \(httpResponse.statusCode))")
        }
    }
}

// MARK: - Fetch Result

struct FetchResult {
    let appName: String
    let subscriptionName: String
    let offerName: String
    let codesImported: Int
    let codesSkipped: Int
}
