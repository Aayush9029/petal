public enum FloatingCapsuleBackgroundStyle: String, CaseIterable, Identifiable, Sendable, Codable {
    case solid
    case liquidGlass

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .solid:
            return "Solid"
        case .liquidGlass:
            return "Liquid Glass"
        }
    }

    public var description: String {
        switch self {
        case .solid:
            return "An opaque background."
        case .liquidGlass:
            return "A translucent Liquid Glass background."
        }
    }
}
