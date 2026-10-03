import Shared

public struct CloudCleanupConfiguration: Equatable, Sendable {
    public var connection: CloudConnection
    public var model: CloudModel.ID
    public var systemPrompt: String
    public var tools: Set<CloudTool>

    public init(connection: CloudConnection, model: CloudModel.ID, systemPrompt: String, tools: Set<CloudTool> = []) {
        self.connection = connection
        self.model = model
        self.systemPrompt = systemPrompt
        self.tools = tools
    }
}
