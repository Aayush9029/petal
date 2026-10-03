import Shared

public struct CloudModelSearchResults: Equatable, Sendable {
    public var suggested: IdentifiedArrayOf<CloudModel>
    public var all: IdentifiedArrayOf<CloudModel>
    public var customID: CloudModel.ID?

    public init(suggested: IdentifiedArrayOf<CloudModel> = [], all: IdentifiedArrayOf<CloudModel> = [], customID: CloudModel.ID? = nil) {
        self.suggested = suggested
        self.all = all
        self.customID = customID
    }

    public var isEmpty: Bool {
        suggested.isEmpty && all.isEmpty && customID == nil
    }
}
