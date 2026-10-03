import Shared

extension CloudPromptVariable {
    var symbol: String {
        switch self {
        case .name: "person"
        case .firstName: "signature"
        case .app: "app"
        case .window: "macwindow"
        case .language: "character.bubble"
        case .region: "flag"
        case .timeZone: "globe"
        }
    }
}
