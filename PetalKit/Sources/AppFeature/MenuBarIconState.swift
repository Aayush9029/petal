import Foundation

public enum MenuBarIconState: Equatable {
    case idle
    case recording
    case working
    case error

    public var isAnimated: Bool {
        switch self {
        case .recording, .working: return true
        case .idle, .error: return false
        }
    }
}
