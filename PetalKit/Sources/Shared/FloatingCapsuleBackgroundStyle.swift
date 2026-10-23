public enum FloatingCapsuleBackgroundStyle: String, CaseIterable, Identifiable, Sendable, Codable {
    case future
    case liquidGlass

    /// Reads saved values of earlier builds: "liquid" became Future, and the
    /// removed "solid" style moves to Glass.
    public init?(rawValue: String) {
        switch rawValue {
        case "future", "liquid":
            self = .future
        case "liquidGlass", "solid":
            self = .liquidGlass
        default:
            return nil
        }
    }

    public var rawValue: String {
        switch self {
        case .future: "future"
        case .liquidGlass: "liquidGlass"
        }
    }

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .future:
            return "Future"
        case .liquidGlass:
            return "Liquid Glass"
        }
    }

    public var description: String {
        switch self {
        case .future:
            return "Dark glass that rises, ripples, and splits like a drop of liquid."
        case .liquidGlass:
            return "Clear Liquid Glass that morphs and merges like a drop of liquid."
        }
    }
}
