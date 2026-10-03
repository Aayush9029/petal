import Shared

extension CloudPromptPreset {
    var symbol: String {
        switch self {
        case .cleanUp: "text.badge.checkmark"
        case .email: "envelope"
        case .notes: "list.bullet"
        case .professional: "briefcase"
        case .aiPrompt: "terminal"
        case .assistant: "sparkles"
        }
    }
}
