import Shared

extension CloudPromptPreset {
    var symbol: String {
        switch self {
        case .cleanUp: "wand.and.rays"
        case .email: "envelope"
        case .notes: "list.bullet"
        case .professional: "briefcase"
        case .aiPrompt: "brain"
        case .assistant: "bubble.left.and.text.bubble.right"
        }
    }

    /// Fits under the title on a style card.
    var shortSummary: String {
        switch self {
        case .cleanUp: "Fixes fillers"
        case .email: "Greeting and sign-off"
        case .notes: "Short bullets"
        case .professional: "Polished tone"
        case .aiPrompt: "For AI agents"
        case .assistant: "Does what you ask"
        }
    }
}
