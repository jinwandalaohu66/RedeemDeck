//
//  KeychainService.swift
//  AppStoreCodes
//
//  Created by Matteo Comisso on 08/12/2025.
//

import Foundation
import Security

enum KeychainError: LocalizedError {
    case duplicateItem
    case itemNotFound
    case unexpectedStatus(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .duplicateItem:
            return "Item already exists in keychain"
        case .itemNotFound:
            return "Item not found in keychain"
        case .unexpectedStatus(let status):
            return "Keychain error: \(status)"
        case .invalidData:
            return "Invalid data format"
        }
    }
}

final class KeychainService {
    static let shared = KeychainService()

    private let service = "com.appstorecodesmanager.api"
    private let trackingTokenAccount = "tracking-api-token"

    private init() {}

    // MARK: - API Key Storage

    func saveAPIKey(_ key: Data, keyId: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "apiKey-\(keyId)",
            kSecValueData as String: key
        ]

        // Delete existing item first
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func getAPIKey(keyId: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "apiKey-\(keyId)",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            throw KeychainError.unexpectedStatus(status)
        }

        guard let data = result as? Data else {
            throw KeychainError.invalidData
        }

        return data
    }

    func deleteAPIKey(keyId: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "apiKey-\(keyId)"
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func hasAPIKey(keyId: String) -> Bool {
        do {
            _ = try getAPIKey(keyId: keyId)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Tracking API Token Storage

    /// Stores a backend-specific bearer token outside UserDefaults and the app bundle.
    func saveTrackingAPIToken(_ token: String, forAPIBaseURL apiBaseURL: String) throws {
        try saveTrackingAPIToken(token, account: trackingTokenAccount(for: apiBaseURL))
    }

    private func saveTrackingAPIToken(_ token: String, account: String) throws {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = normalizedToken.data(using: .utf8), !normalizedToken.isEmpty else {
            throw KeychainError.invalidData
        }

        let query = trackingTokenQuery(account: account)
        SecItemDelete(query as CFDictionary)

        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func getTrackingAPIToken(forAPIBaseURL apiBaseURL: String) throws -> String {
        try getTrackingAPIToken(account: trackingTokenAccount(for: apiBaseURL))
    }

    private func getTrackingAPIToken(account: String) throws -> String {
        var query = trackingTokenQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            throw KeychainError.unexpectedStatus(status)
        }
        guard let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return token
    }

    func deleteTrackingAPIToken(forAPIBaseURL apiBaseURL: String) throws {
        try deleteTrackingAPIToken(account: trackingTokenAccount(for: apiBaseURL))
    }

    private func deleteTrackingAPIToken(account: String) throws {
        let status = SecItemDelete(trackingTokenQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func hasTrackingAPIToken(forAPIBaseURL apiBaseURL: String) -> Bool {
        (try? getTrackingAPIToken(forAPIBaseURL: apiBaseURL)) != nil
    }

    private func trackingTokenAccount(for apiBaseURL: String) -> String {
        "\(trackingTokenAccount)-\(apiBaseURL.lowercased())"
    }

    private func trackingTokenQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    // MARK: - Issuer ID Storage

    func saveIssuerId(_ issuerId: String) throws {
        guard let data = issuerId.data(using: .utf8) else {
            throw KeychainError.invalidData
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "issuerId",
            kSecValueData as String: data
        ]

        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func getIssuerId() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "issuerId",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            throw KeychainError.unexpectedStatus(status)
        }

        guard let data = result as? Data,
              let issuerId = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }

        return issuerId
    }

}
