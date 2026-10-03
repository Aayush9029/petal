import Shared

public struct CloudCleanupResult: Equatable, Sendable {
    public var text: String
    public var model: CloudModel.ID?
    public var toolCalls: [String]
    public var requestCount: Int
    public var elapsed: Duration

    public init(text: String, model: CloudModel.ID? = nil, toolCalls: [String] = [], requestCount: Int = 1, elapsed: Duration = .zero) {
        self.text = text
        self.model = model
        self.toolCalls = toolCalls
        self.requestCount = requestCount
        self.elapsed = elapsed
    }
}
