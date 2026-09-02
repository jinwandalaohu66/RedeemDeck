import Foundation

actor BackupFileReader {
    static let shared = BackupFileReader()

    func read(from url: URL) throws -> Data {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            return try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw BackupCodecError.invalidArchive
        }
    }
}
