import Shared

extension CloudPromptVariable {
    var symbol: String {
        switch self {
        case .date: "calendar"
        case .time: "clock"
        case .timeZone: "globe"
        case .app: "macwindow"
        case .name: "person"
        case .language: "character.bubble"
        }
    }
}
