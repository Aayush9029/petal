import CasePaths

@CasePathable
public enum CloudPromptVariable: String, CaseIterable, Identifiable, Sendable {
    case name
    case firstName = "first_name"
    case app
    case window
    case language
    case region
    case timeZone = "time_zone"

    public var id: String { rawValue }

    public var token: String { "{{\(rawValue)}}" }

    public var title: String {
        switch self {
        case .name: "Full Name"
        case .firstName: "First Name"
        case .app: "Current App"
        case .window: "Window Title"
        case .language: "Language"
        case .region: "Region"
        case .timeZone: "Time Zone"
        }
    }

    public var source: String {
        switch self {
        case .name: "Your full name from your Mac account"
        case .firstName: "Your first name from your Mac account"
        case .app: "The app that you dictate into"
        case .window: "The title of the front window, such as an email subject or a chat name"
        case .language: "Your Mac's primary language"
        case .region: "Your Mac's region, which sets date, number, and currency formats"
        case .timeZone: "Your Mac's time zone"
        }
    }

    public var example: String {
        switch self {
        case .name: "Alex Kim"
        case .firstName: "Alex"
        case .app: "Slack"
        case .window: "Re: Q4 launch plan"
        case .language: "English"
        case .region: "United States"
        case .timeZone: "America/New_York"
        }
    }
}
