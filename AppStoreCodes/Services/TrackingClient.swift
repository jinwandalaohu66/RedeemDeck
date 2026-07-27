import Foundation

enum TrackingSettingsKeys {
    static let apiBaseURL = "trackingAPIBaseURL"
    static let isEnabled = "trackInteraction"
}

struct TrackingConfiguration: Sendable, Equatable {
    let baseURL: URL
    let apiToken: String

    init(baseURL: URL, apiToken: String) throws {
        guard baseURL.scheme?.lowercased() == "https",
              baseURL.host != nil,
              baseURL.user == nil,
              baseURL.password == nil,
              baseURL.query == nil,
              baseURL.fragment == nil else {
            throw TrackingClientError.invalidBaseURL
        }
        let token = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw TrackingClientError.missingAPIToken
        }
        self.baseURL = baseURL
        self.apiToken = token
    }

    init(baseURLString: String, apiToken: String) throws {
        let value = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value) else {
            throw TrackingClientError.invalidBaseURL
        }
        try self.init(baseURL: url, apiToken: apiToken)
    }
}

struct TrackingLink: Codable, Equatable, Sendable {
    let id: String
    let shortURL: URL
    let createdAt: Date
    let expiresAt: Date?
}

struct TrackingLinkStatus: Codable, Equatable, Sendable {
    let id: String
    let firstSeenAt: Date?
    let lastSeenAt: Date?
    let visitCount: Int
}

enum TrackingClientError: LocalizedError, Equatable {
    case invalidBaseURL
    case missingAPIToken
    case invalidDestinationURL
    case invalidResponse
    case unauthorized
    case conflict
    case requestFailed(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Enter a valid HTTPS tracking API domain."
        case .missingAPIToken:
            return "Enter the tracking API token."
        case .invalidDestinationURL:
            return "This code does not have a valid redemption URL."
        case .invalidResponse:
            return "The tracking service returned an invalid response."
        case .unauthorized:
            return "The tracking API token was rejected."
        case .conflict:
            return "This code is already registered with a different redemption URL."
        case .requestFailed(let statusCode):
            return "The tracking service request failed (HTTP \(statusCode))."
        }
    }
}

protocol TrackingClientProtocol: Sendable {
    func health(configuration: TrackingConfiguration) async throws
    func createLink(
        clientId: UUID,
        destinationURL: URL,
        expiresAt: Date?,
        configuration: TrackingConfiguration
    ) async throws -> TrackingLink
    func statuses(
        linkIDs: [String],
        configuration: TrackingConfiguration
    ) async throws -> [TrackingLinkStatus]
}

final class TrackingClient: TrackingClientProtocol, @unchecked Sendable {
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = Self.fractionalDateFormatter.date(from: value)
                ?? Self.dateFormatter.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an ISO 8601 date"
            )
        }
    }

    func health(configuration: TrackingConfiguration) async throws {
        let request = makeRequest(path: "v1/health", method: "GET", configuration: configuration)
        let (_, response) = try await session.data(for: request)
        try validate(response)
    }

    func createLink(
        clientId: UUID,
        destinationURL: URL,
        expiresAt: Date?,
        configuration: TrackingConfiguration
    ) async throws -> TrackingLink {
        guard destinationURL.scheme?.lowercased() == "https" else {
            throw TrackingClientError.invalidDestinationURL
        }
        var request = makeRequest(path: "v1/links", method: "POST", configuration: configuration)
        request.setValue(clientId.uuidString, forHTTPHeaderField: "Idempotency-Key")
        request.httpBody = try encoder.encode(CreateLinkRequest(
            clientId: clientId.uuidString,
            destinationURL: destinationURL,
            expiresAt: expiresAt
        ))
        let (data, response) = try await session.data(for: request)
        try validate(response)
        do {
            return try decoder.decode(TrackingLink.self, from: data)
        } catch {
            throw TrackingClientError.invalidResponse
        }
    }

    func statuses(
        linkIDs: [String],
        configuration: TrackingConfiguration
    ) async throws -> [TrackingLinkStatus] {
        guard !linkIDs.isEmpty, linkIDs.count <= 100 else {
            return []
        }
        var request = makeRequest(path: "v1/links/status", method: "POST", configuration: configuration)
        request.httpBody = try encoder.encode(StatusRequest(ids: linkIDs))
        let (data, response) = try await session.data(for: request)
        try validate(response)
        do {
            return try decoder.decode(StatusResponse.self, from: data).links
        } catch {
            throw TrackingClientError.invalidResponse
        }
    }

    private func makeRequest(
        path: String,
        method: String,
        configuration: TrackingConfiguration
    ) -> URLRequest {
        let url = path.split(separator: "/").reduce(configuration.baseURL) {
            $0.appendingPathComponent(String($1))
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("Bearer \(configuration.apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if method == "POST" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func validate(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else {
            throw TrackingClientError.invalidResponse
        }
        switch response.statusCode {
        case 200..<300:
            return
        case 401, 403:
            throw TrackingClientError.unauthorized
        case 409:
            throw TrackingClientError.conflict
        default:
            throw TrackingClientError.requestFailed(statusCode: response.statusCode)
        }
    }

    private struct CreateLinkRequest: Encodable {
        let clientId: String
        let destinationURL: URL
        let expiresAt: Date?
    }

    private struct StatusRequest: Encodable {
        let ids: [String]
    }

    private struct StatusResponse: Decodable {
        let links: [TrackingLinkStatus]
    }

    private static let fractionalDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let dateFormatter = ISO8601DateFormatter()
}
