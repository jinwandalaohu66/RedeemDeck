import Foundation

nonisolated enum CodeKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case appPromo
    case oneTimeOffer
    case customOffer
    case sandbox
    case unknown

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .appPromo: String(localized: "App promo code")
        case .oneTimeOffer: String(localized: "One-time offer code")
        case .customOffer: String(localized: "Custom offer code")
        case .sandbox: String(localized: "Sandbox code")
        case .unknown: String(localized: "Unspecified code")
        }
    }
}

nonisolated enum CodeEnvironment: String, CaseIterable, Codable, Identifiable, Sendable {
    case production
    case sandbox

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .production: String(localized: "Production")
        case .sandbox: String(localized: "Sandbox")
        }
    }
}

nonisolated enum AppPlatform: String, CaseIterable, Codable, Identifiable, Sendable {
    case iOS
    case iPadOS
    case macOS
    case tvOS
    case visionOS
    case multiplatform

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .iOS: "iOS"
        case .iPadOS: "iPadOS"
        case .macOS: "macOS"
        case .tvOS: "tvOS"
        case .visionOS: "visionOS"
        case .multiplatform: String(localized: "Multiple platforms")
        }
    }
}

nonisolated enum CodeLifecycleStatus: String, CaseIterable, Codable, Identifiable, Sendable {
    case available
    case pending
    case sent
    case expired

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .available: String(localized: "Available")
        case .pending: String(localized: "Pending")
        case .sent: String(localized: "Sent")
        case .expired: String(localized: "Expired")
        }
    }
}

nonisolated enum CodeBrowserFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case available
    case pending
    case sent
    case expired

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .all: String(localized: "All")
        case .available: String(localized: "Available")
        case .pending: String(localized: "Pending")
        case .sent: String(localized: "Sent")
        case .expired: String(localized: "Expired")
        }
    }

    func includes(_ status: CodeLifecycleStatus) -> Bool {
        switch self {
        case .all: true
        case .available: status == .available
        case .pending: status == .pending
        case .sent: status == .sent
        case .expired: status == .expired
        }
    }
}
