public enum FloatingCapsuleBackgroundStyle: String, CaseIterable, Identifiable, Sendable, Codable {
    case liquid
    case liquidGlass
    case solid

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .liquid:
            return "Liquid"
        case .solid:
            return "Solid"
        case .liquidGlass:
            return "Liquid Glass"
        }
    }

    public var description: String {
        switch self {
        case .liquid:
            return "Dark glass that rises, ripples, and splits like a drop of liquid."
        case .solid:
            return "An opaque background."
        case .liquidGlass:
            return "A translucent Liquid Glass background."
        }
    }
}
