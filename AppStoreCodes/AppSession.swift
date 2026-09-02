import Foundation
import Observation

@MainActor
@Observable
final class AppSession {
    private(set) var dataRevision = 0

    func dataDidChange() {
        dataRevision &+= 1
    }
}
