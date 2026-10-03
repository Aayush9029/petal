public struct CloudModel: Hashable, Identifiable, Sendable {
    public typealias ID = Tagged<Self, String>

    public var id: ID
    public var name: String?
    public var note: String?

    public init(id: ID, name: String? = nil, note: String? = nil) {
        self.id = id
        self.name = name
        self.note = note
    }

    public var title: String {
        name ?? id.rawValue
    }
}
