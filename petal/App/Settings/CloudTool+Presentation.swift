import CloudCleanupClient

extension CloudTool {
    var title: String {
        switch self {
        case .dateTime: "Date and Time"
        case .webSearch: "Web Search"
        case .clipboard: "Clipboard"
        case .selectedText: "Selected Text"
        }
    }

    var summary: String {
        switch self {
        case .dateTime: "Turns words like “next Friday” into exact dates."
        case .webSearch: "Looks up facts you ask for. Charged per search."
        case .clipboard: "Reads what you copied when you say “this”."
        case .selectedText: "Rewrites or replies to the text you selected."
        }
    }

    var symbol: String {
        switch self {
        case .dateTime: "calendar.badge.clock"
        case .webSearch: "globe"
        case .clipboard: "doc.on.clipboard"
        case .selectedText: "text.cursor"
        }
    }
}
