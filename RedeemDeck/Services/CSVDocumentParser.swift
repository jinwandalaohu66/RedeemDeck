import Foundation

private nonisolated enum CSVRowParser {
    static func parse(_ row: String) -> [String]? {
        var fields: [String] = []
        var field = ""
        var isInsideQuotes = false
        var index = row.startIndex

        while index < row.endIndex {
            let character = row[index]
            if character == "\"" {
                let nextIndex = row.index(after: index)
                if isInsideQuotes, nextIndex < row.endIndex, row[nextIndex] == "\"" {
                    field.append("\"")
                    index = row.index(after: nextIndex)
                    continue
                }
                isInsideQuotes.toggle()
            } else if character == ",", !isInsideQuotes {
                fields.append(field)
                field = ""
            } else {
                field.append(character)
            }
            index = row.index(after: index)
        }

        guard !isInsideQuotes else { return nil }
        fields.append(field)
        return fields
    }
}

nonisolated struct CSVImportDates {
    let issueDate: Date
    let expirationDate: Date
    let codeKind: CSVCodeKind

    init(
        url: URL,
        csvContent: String? = nil,
        calendar: Calendar = .current,
        fallbackDate: Date = Date()
    ) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let values = try? url.resourceValues(forKeys: [
            .contentModificationDateKey,
            .creationDateKey,
        ])
        let documentDate = values?.contentModificationDate
            ?? values?.creationDate
            ?? fallbackDate
        let content = csvContent ?? (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let kind = Self.inferCodeKind(from: content)

        issueDate = calendar.startOfDay(for: documentDate)
        codeKind = kind
        expirationDate = Self.defaultExpirationDate(
            for: issueDate,
            codeKind: kind,
            calendar: calendar
        )
    }

    static func defaultExpirationDate(
        for issueDate: Date,
        codeKind: CSVCodeKind = .offer,
        calendar: Calendar = .current
    ) -> Date {
        let issueDay = calendar.startOfDay(for: issueDate)
        switch codeKind {
        case .promo:
            return calendar.date(byAdding: .day, value: 28, to: issueDay) ?? issueDay
        case .offer:
            return calendar.date(byAdding: .month, value: 6, to: issueDay) ?? issueDay
        }
    }

    static func inferCodeKind(from content: String) -> CSVCodeKind {
        let rows = CSVDocumentParser.rows(in: content)
        if let firstField = rows.first?.first {
            let header = firstField
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"\u{FEFF}"))
                .lowercased()
                .filter { $0.isLetter || $0.isNumber }
            if header == "promocode" { return .promo }
            if header == "offercode" { return .offer }
        }

        let hasOfferURL = rows.contains { fields in
            guard fields.count > 1,
                  let components = URLComponents(
                    string: fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
                  ) else { return false }
            return components.queryItems?.contains {
                $0.name.caseInsensitiveCompare("ctx") == .orderedSame
                    && $0.value?.caseInsensitiveCompare("offercodes") == .orderedSame
            } == true
        }
        return hasOfferURL ? .offer : .promo
    }
}

nonisolated enum CSVDocumentParser {
    static func parse(_ content: String, targetAppStoreId: String?) throws -> [ParsedCode] {
        var results: [ParsedCode] = []
        var discoveredAppStoreId = targetAppStoreId

        for components in rows(in: content) {
            try Task.checkCancellation()
            guard let first = components.first else { continue }
            let code = normalized(first)
            if isHeader(code) { continue }
            guard isValidCode(code) else { continue }

            let suppliedURL = components.count > 1 ? normalized(components[1]) : ""
            let urlAppStoreId = suppliedURL.isEmpty ? nil : appStoreID(from: suppliedURL)
            if let targetAppStoreId, let urlAppStoreId,
               targetAppStoreId != urlAppStoreId {
                throw CSVImportError.appStoreIdMismatch
            }
            if let urlAppStoreId {
                if let discoveredAppStoreId, discoveredAppStoreId != urlAppStoreId {
                    throw CSVImportError.appStoreIdMismatch
                }
                discoveredAppStoreId = urlAppStoreId
            }
            guard let appStoreId = urlAppStoreId ?? targetAppStoreId else {
                if suppliedURL.isEmpty { throw CSVImportError.targetAppRequired }
                continue
            }
            results.append(ParsedCode(
                code: code,
                redemptionURL: suppliedURL.isEmpty
                    ? redemptionURL(code: code, appStoreId: appStoreId)
                    : suppliedURL,
                appStoreId: appStoreId
            ))
        }
        return results
    }

    static func containsEmbeddedAppStoreID(in content: String) -> Bool {
        detectedAppStoreID(in: content) != nil
    }

    static func detectedAppStoreID(in content: String) -> String? {
        rows(in: content).lazy.compactMap { fields in
            guard fields.count > 1 else { return nil }
            return appStoreID(from: normalized(fields[1]))
        }.first
    }

    static func rows(in content: String) -> [[String]] {
        content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .compactMap(CSVRowParser.parse)
    }

    private static func isValidCode(_ code: String) -> Bool {
        guard (1...64).contains(code.utf8.count) else { return false }
        return code.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
        }
    }

    private static func normalized(_ field: String) -> String {
        field.trimmingCharacters(
            in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}"))
        )
    }

    private static func isHeader(_ field: String) -> Bool {
        let value = field.lowercased().filter { $0.isLetter || $0.isNumber }
        return value == "code" || value == "offercode" || value == "promocode"
    }

    private static func redemptionURL(code: String, appStoreId: String) -> String {
        var components = URLComponents(string: "https://apps.apple.com/redeem")!
        components.queryItems = [
            URLQueryItem(name: "ctx", value: "offercodes"),
            URLQueryItem(name: "id", value: appStoreId),
            URLQueryItem(name: "code", value: code),
        ]
        return components.url!.absoluteString
    }

    private static func appStoreID(from urlString: String) -> String? {
        guard let url = URL(string: urlString),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        return components.queryItems?.first { $0.name == "id" }?.value
    }
}

nonisolated enum CSVFileReader {
    static func read(_ url: URL) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw CSVImportError.fileReadError
        }
    }
}
