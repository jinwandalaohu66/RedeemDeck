import Foundation

enum UserFacingError {
    static func message(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }
        return String(localized: "The operation could not be completed. Please try again.")
    }
}
