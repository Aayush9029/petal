import Observation

@MainActor
@Observable
public final class FloatingCapsuleState {
    public enum Phase: Equatable {
        case hidden
        case recording
        case confirmCancel
        case trimming
        case speeding
        case transcribing
        case refining
        case copiedToClipboard
        case accessibilityPrompt
        case accessibilityEnabled
        case error(String)
    }

    public var phase: Phase = .hidden
    public var level: Double = 0
    public var transcriptionProgress: Double = 0
    public var cancelCountdownActive: Bool = false
    public var onRecordingTapped: (() -> Void)?
    public var onAccessibilityTapped: (() -> Void)?

    public init() {}
}
