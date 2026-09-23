import CasePaths

/// The raw values are the exact control-line tokens S1-mini was trained on.
@CasePathable
public enum S1MiniStyling: String, CaseIterable, Identifiable, Sendable, Codable {
    case casual
    case semiCasual = "semi-casual"
    case semiFormal = "semi-formal"
    case formal

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .casual: "Casual"
        case .semiCasual: "Relaxed"
        case .semiFormal: "Standard"
        case .formal: "Formal"
        }
    }

    public static let exampleInput = "um so like im gonna be late lol theres this super cute dog outside and uh i literally cant just walk past him"

    /// Measured S1-mini output for `exampleInput`.
    public var example: String {
        switch self {
        case .casual: "um so im gonna be late lol. theres this super cute dog outside and i literally cant just walk past him"
        case .semiCasual: "um so like I'm gonna be late, lol. there's this super cute dog outside, and I literally can't just walk past him"
        case .semiFormal: "So I'm going to be late. There's this super cute dog outside, and I literally can't just walk past him."
        case .formal: "So I am going to be late. There is this super cute dog outside, and I literally cannot just walk past him."
        }
    }
}
