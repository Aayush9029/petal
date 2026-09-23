import CasePaths

@CasePathable
public enum S1MiniStructure: String, CaseIterable, Identifiable, Sendable, Codable {
    case prose
    case lists

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .prose: "Paragraphs"
        case .lists: "Allow Lists"
        }
    }
}
