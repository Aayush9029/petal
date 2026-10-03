import CasePaths

@CasePathable
public enum CloudPromptVariable: String, CaseIterable, Identifiable, Sendable {
    case date
    case time
    case timeZone = "time_zone"
    case app
    case name
    case language

    public var id: String { rawValue }

    public var token: String { "{{\(rawValue)}}" }

    public var title: String {
        switch self {
        case .date: "Date"
        case .time: "Time"
        case .timeZone: "Time Zone"
        case .app: "Current App"
        case .name: "Your Name"
        case .language: "Language"
        }
    }

    public var example: String {
        switch self {
        case .date: "Saturday, October 3, 2026"
        case .time: "5:42 PM"
        case .timeZone: "America/New_York"
        case .app: "Slack"
        case .name: "Alex Kim"
        case .language: "English"
        }
    }
}
