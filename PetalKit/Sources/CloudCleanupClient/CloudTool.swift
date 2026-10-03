import CasePaths

@CasePathable
public enum CloudTool: String, CaseIterable, Hashable, Sendable {
    case dateTime
    case webSearch
    case clipboard
    case selectedText

    public var functionName: String? {
        switch self {
        case .dateTime: "get_current_date_time"
        case .clipboard: "get_clipboard_text"
        case .selectedText: "get_selected_text"
        case .webSearch: nil
        }
    }
}
