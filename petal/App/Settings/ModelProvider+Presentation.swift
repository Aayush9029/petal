import Shared
import SwiftUI

extension ModelProvider {
    var tint: Color {
        switch self {
        case .appleSpeech: .orange
        case .mlxAudio: .purple
        case .nvidia: .green
        case .whisperKit: .teal
        case .voxtralCore: .red
        }
    }
}
