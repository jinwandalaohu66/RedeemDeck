import Foundation

struct CodeRetrievalRequest: Identifiable, Hashable {
    let id: UUID
    let app: AppSummary
    let selectionID: UUID?
    let categoryID: UUID?
    let quantity: Int?

    static func new(
        app: AppSummary,
        categoryID: UUID,
        quantity: Int
    ) -> CodeRetrievalRequest {
        CodeRetrievalRequest(
            id: UUID(),
            app: app,
            selectionID: nil,
            categoryID: categoryID,
            quantity: quantity
        )
    }

    static func resume(
        app: AppSummary,
        selectionID: UUID
    ) -> CodeRetrievalRequest {
        CodeRetrievalRequest(
            id: selectionID,
            app: app,
            selectionID: selectionID,
            categoryID: nil,
            quantity: nil
        )
    }
}

struct CodeQuantityPrompt: Identifiable {
    let id = UUID()
    let app: AppSummary
    let categories: [CodeCategorySummary]
}

enum LibraryRoute: Hashable {
    case manage(AppSummary)
    case category(AppSummary, CodeCategorySummary)
    case code(AppSummary, CodeCategorySummary, CodeRowSummary)
    case retrieval(CodeRetrievalRequest)
}

enum RetrievalOutput: String, CaseIterable, Identifiable {
    case codes
    case links
    case qrCodes

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .codes: String(localized: "Codes")
        case .links: String(localized: "Links")
        case .qrCodes: String(localized: "Poster")
        }
    }
}
