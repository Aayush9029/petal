import Shared
import SwiftUI

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

    var tint: Color {
        switch self {
        case .cleanUp: .blue
        case .email: .cyan
        case .notes: .yellow
        case .professional: .brown
        case .aiPrompt: .pink
        case .assistant: .green
        }
    }

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
