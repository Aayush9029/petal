import Foundation

public enum LocalCleanupError: LocalizedError, Sendable, Equatable {
    case notDownloaded
    case missingStopToken

    public var errorDescription: String? {
        switch self {
        case .notDownloaded: "Download S1-mini before you use it for cleanup."
        case .missingStopToken: "The S1-mini tokenizer has no end-of-turn token."
        }
    }
}
