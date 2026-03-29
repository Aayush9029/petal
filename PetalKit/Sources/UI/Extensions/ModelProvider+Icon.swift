import Assets
import Shared
import SwiftUI

public extension ModelProvider {
    var icon: Image {
        switch self {
        case .appleSpeech: .swiftLogo
        case .fluidAudio: .qwen
        case .nvidia: .nvidia
        case .whisperKit: .openai
        case .cohere: .cohere
        case .voxtralCore: .mistral
        }
    }
}
