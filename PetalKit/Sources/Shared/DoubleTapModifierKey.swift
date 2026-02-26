public enum DoubleTapModifierKey: String, CaseIterable, Identifiable, Sendable, Codable {
    case fn = "fn"
    case command = "command"
    case option = "option"
    case control = "control"
    case shift = "shift"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fn: "Fn (Globe)"
        case .command: "Command (⌘)"
        case .option: "Option (⌥)"
        case .control: "Control (⌃)"
        case .shift: "Shift (⇧)"
        }
    }
}
