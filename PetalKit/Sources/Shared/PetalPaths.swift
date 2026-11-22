import Dependencies
import Foundation

package enum PetalPaths {
    package static let documents: URL = {
        // Retention changes can delete an entire directory during a test.
        if isTesting {
            return URL.temporaryDirectory.appending(path: "petal-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        }
        return URL.documentsDirectory.appending(path: "petal", directoryHint: .isDirectory)
    }()

    package static let history = documents.appending(path: "history", directoryHint: .isDirectory)
}
