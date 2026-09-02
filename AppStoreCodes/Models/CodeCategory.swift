import Foundation
import SwiftData

/// A stable business grouping such as “Pro Monthly → 50% for 3 months”.
/// Import batches are implementation history beneath this user-facing category.
@Model
final class CodeCategory {
    var id: UUID = UUID()
    var name: String = ""
    var productName: String = ""
    var productID: String?
    var offerReferenceName: String?
    var notes: String?
    var createdAt: Date = Date()
    var archivedAt: Date?

    var app: AppRecord?

    @Relationship(deleteRule: .cascade, inverse: \CodeBatch.category)
    var batches: [CodeBatch]?

    init(
        name: String,
        productName: String,
        productID: String? = nil,
        offerReferenceName: String? = nil,
        app: AppRecord? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.productName = productName
        self.productID = productID
        self.offerReferenceName = offerReferenceName
        self.createdAt = Date()
        self.app = app
    }

    var isArchived: Bool {
        archivedAt != nil
    }
}

nonisolated struct CodeCategoryInput: Sendable {
    let existingID: UUID?
    let name: String
    let productName: String
    let productID: String?
    let offerReferenceName: String?

    static func existing(_ id: UUID) -> CodeCategoryInput {
        CodeCategoryInput(
            existingID: id,
            name: "",
            productName: "",
            productID: nil,
            offerReferenceName: nil
        )
    }

    static func new(
        name: String,
        productName: String,
        productID: String? = nil,
        offerReferenceName: String? = nil
    ) -> CodeCategoryInput {
        CodeCategoryInput(
            existingID: nil,
            name: name,
            productName: productName,
            productID: productID,
            offerReferenceName: offerReferenceName
        )
    }
}
