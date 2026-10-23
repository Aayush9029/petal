/// How the floating capsule moves when the capsule phase changes.
enum CapsuleCue: Equatable, Sendable {
    case none
    /// A drop appears, rises, and sends a ripple.
    case present
    /// The glass springs to the new content size.
    case resize
    /// The glass springs to the new size, wobbles, and sends a small ripple.
    case pulse
    /// The glass merges, shrinks, and lifts away.
    case dismiss

    static func transition(
        from old: FloatingCapsuleState.Phase,
        to new: FloatingCapsuleState.Phase
    ) -> Self {
        switch (old, new) {
        case (.hidden, .hidden):
            return .none
        case (_, .hidden):
            return .dismiss
        case (.hidden, _):
            return .present
        default:
            guard old != new else { return .none }
            return Stage(old) == Stage(new) ? .resize : .pulse
        }
    }

    /// The stage can first appear while a phase is already showing, so a
    /// capsule that is not on screen counts as hidden.
    static func transition(
        from old: FloatingCapsuleState.Phase,
        to new: FloatingCapsuleState.Phase,
        isPresented: Bool
    ) -> Self {
        transition(from: isPresented ? old : .hidden, to: new)
    }

    private enum Stage {
        case capture
        case processing
        case refining
        case status

        init(_ phase: FloatingCapsuleState.Phase) {
            switch phase {
            case .hidden, .recording, .confirmCancel:
                self = .capture
            case .trimming, .speeding, .transcribing:
                self = .processing
            case .refining:
                self = .refining
            case .copiedToClipboard, .accessibilityPrompt, .accessibilityEnabled, .error:
                self = .status
            }
        }
    }
}

extension FloatingCapsuleState.Phase {
    /// Trimming, speeding, transcribing, and refining: the highlight orbits the rim.
    var isProcessing: Bool {
        switch self {
        case .trimming, .speeding, .transcribing, .refining: true
        default: false
        }
    }

    /// Colour of the bloom the label casts inside the Future glass.
    var capsuleGlow: SIMD3<Double> {
        switch self {
        case .hidden, .recording, .confirmCancel:
            return [0.30, 0.12, 0.19]
        case .trimming, .speeding, .transcribing:
            return [0.16, 0.14, 0.30]
        case .refining:
            return [0.24, 0.10, 0.34]
        case .copiedToClipboard, .accessibilityEnabled:
            return [0.08, 0.24, 0.13]
        case .accessibilityPrompt:
            return [0.06, 0.14, 0.34]
        case .error:
            return [0.32, 0.17, 0.04]
        }
    }
}
