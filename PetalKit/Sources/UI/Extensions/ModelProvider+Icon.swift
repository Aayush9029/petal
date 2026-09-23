import Assets
import Shared
import SwiftUI

public extension ModelProvider {
    var icon: Image {
        switch self {
        case .appleSpeech: .swiftLogo
        case .mlxAudio: .qwen
        case .nvidia: .nvidia
        case .whisperKit: .openai
        case .voxtralCore: .mistral
        }
    }
}
