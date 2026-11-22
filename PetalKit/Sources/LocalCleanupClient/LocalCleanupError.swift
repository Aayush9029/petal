import Foundation

public enum LocalCleanupError: LocalizedError, Sendable, Equatable {
    case notDownloaded
    case incompleteDownload
    case missingStopToken

    public var errorDescription: String? {
        switch self {
        case .notDownloaded: "Download Petal W1 before you use it for cleanup."
        case .incompleteDownload: "The Petal W1 download is incomplete."
        case .missingStopToken: "The Petal W1 tokenizer has no end-of-turn token."
        }
    }
}
