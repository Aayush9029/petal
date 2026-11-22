import CasePaths

@CasePathable
@dynamicMemberLookup
public enum ModelDownloadState: Sendable, Equatable {
    case notDownloaded
    case preparing
    case downloading(Progress)
    case paused(Progress)
    case downloaded
    case failed(String)

    public struct Progress: Sendable, Equatable {
        public var fraction: Double
        public var statusText: String
        public var speedText: String?

        public init(fraction: Double, statusText: String, speedText: String? = nil) {
            self.fraction = min(max(fraction, 0), 1)
            self.statusText = statusText
            if let speedText {
                self.speedText = speedText
            } else if let start = statusText.lastIndex(of: "("), let end = statusText.lastIndex(of: ")"), start < end {
                let speed = statusText[statusText.index(after: start)..<end]
                self.speedText = speed.hasSuffix("/s") ? String(speed) : nil
            }
        }

        public var summaryText: String {
            let percent = Int((fraction * 100).rounded())
            if let speedText {
                return "\(percent)% - \(speedText)"
            }
            return "\(percent)%"
        }
    }

    public var isActive: Bool {
        switch self {
        case .preparing, .downloading: true
        case .notDownloaded, .paused, .downloaded, .failed: false
        }
    }

    public var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }

    public var isDownloaded: Bool {
        if case .downloaded = self { return true }
        return false
    }

    public var progress: Progress? {
        switch self {
        case let .downloading(p), let .paused(p): p
        default: nil
        }
    }
}
