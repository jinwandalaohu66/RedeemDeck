import Foundation

extension String {
    nonisolated var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated var nilIfBlank: String? {
        let value = trimmed
        return value.isEmpty ? nil : value
    }
}
