//
//  JWTGenerator.swift
//  AppStoreCodes
//
//  Created by Matteo Comisso on 08/12/2025.
//

import Foundation
import CryptoKit

enum JWTError: LocalizedError {
    case invalidPrivateKey
    case encodingFailed
    case signingFailed

    var errorDescription: String? {
        switch self {
        case .invalidPrivateKey:
            return "Invalid private key format. Ensure you're using a valid .p8 file."
        case .encodingFailed:
            return "Failed to encode JWT components."
        case .signingFailed:
            return "Failed to sign the JWT token."
        }
    }
}

struct JWTGenerator {
    private let keyId: String
    private let issuerId: String
    private let privateKey: P256.Signing.PrivateKey

    /// Initialize with API credentials
    /// - Parameters:
    ///   - keyId: The Key ID from App Store Connect
    ///   - issuerId: The Issuer ID from App Store Connect
    ///   - privateKeyPEM: The contents of the .p8 private key file
    init(keyId: String, issuerId: String, privateKeyPEM: String) throws {
        self.keyId = keyId
        self.issuerId = issuerId

        // Parse the PEM format private key
        let cleanedKey = privateKeyPEM
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: " ", with: "")

        guard let keyData = Data(base64Encoded: cleanedKey) else {
            throw JWTError.invalidPrivateKey
        }

        do {
            self.privateKey = try P256.Signing.PrivateKey(derRepresentation: keyData)
        } catch {
            throw JWTError.invalidPrivateKey
        }
    }

    /// Generate a signed JWT token
    /// - Parameter expirationMinutes: Token validity in minutes (max 20 for most operations)
    /// - Returns: Signed JWT string
    func generateToken(expirationMinutes: Int = 15) throws -> String {
        let now = Date()
        let expiration = now.addingTimeInterval(TimeInterval(expirationMinutes * 60))

        // Create header
        let header = JWTHeader(alg: "ES256", kid: keyId, typ: "JWT")

        // Create payload
        let payload = JWTPayload(
            iss: issuerId,
            iat: Int(now.timeIntervalSince1970),
            exp: Int(expiration.timeIntervalSince1970),
            aud: "appstoreconnect-v1"
        )

        // Encode header and payload
        guard let headerData = try? JSONEncoder().encode(header),
              let payloadData = try? JSONEncoder().encode(payload) else {
            throw JWTError.encodingFailed
        }

        let headerBase64 = headerData.base64URLEncodedString()
        let payloadBase64 = payloadData.base64URLEncodedString()

        // Create signing input
        let signingInput = "\(headerBase64).\(payloadBase64)"

        guard let signingData = signingInput.data(using: .utf8) else {
            throw JWTError.encodingFailed
        }

        // Sign with ES256
        do {
            let signature = try privateKey.signature(for: signingData)
            let signatureBase64 = signature.rawRepresentation.base64URLEncodedString()

            return "\(signingInput).\(signatureBase64)"
        } catch {
            throw JWTError.signingFailed
        }
    }
}

// MARK: - JWT Components

private struct JWTHeader: Encodable {
    let alg: String
    let kid: String
    let typ: String
}

private struct JWTPayload: Encodable {
    let iss: String
    let iat: Int
    let exp: Int
    let aud: String
}

// MARK: - Base64 URL Encoding

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
