import Foundation

enum LibrarySortOrder: String, CaseIterable, Identifiable {
    case name
    case available
    case expiring

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .name: String(localized: "Name")
        case .available: String(localized: "Most Available")
        case .expiring: String(localized: "Expiring Soon")
        }
    }
}
