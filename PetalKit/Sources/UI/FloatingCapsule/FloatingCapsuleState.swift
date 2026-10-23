import Observation

@MainActor
@Observable
public final class FloatingCapsuleState {
    public enum Phase: Equatable, Sendable {
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
    public var liveTranscript = ""
    public var showsLiveTranscript: Bool {
        !liveTranscript.isEmpty && (phase == .recording || phase == .confirmCancel || phase == .transcribing)
    }
    public var level: Double = 0
    public var transcriptionProgress: Double = 0
    public var cancelCountdownActive: Bool = false
    public var onRecordingTapped: (() -> Void)?
    public var onCancelRecordingTapped: (() -> Void)?
    public var onAccessibilityTapped: (() -> Void)?

    public init() {}
}

extension FloatingCapsuleState.Phase {
    /// Stable identity of the content a phase shows.
    var contentID: String {
        switch self {
        case .hidden: "hidden"
        case .recording: "recording"
        case .confirmCancel: "confirmCancel"
        case .trimming: "trimming"
        case .speeding: "speeding"
        case .transcribing: "transcribing"
        case .refining: "refining"
        case .copiedToClipboard: "copied"
        case .accessibilityPrompt: "accessibilityPrompt"
        case .accessibilityEnabled: "accessibilityEnabled"
        case .error: "error"
        }
    }
}
