import CasePaths

@CasePathable
public enum S1MiniContext: String, CaseIterable, Identifiable, Sendable, Codable {
    case general
    case email

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .general: "General"
        case .email: "Email"
        }
    }
}
