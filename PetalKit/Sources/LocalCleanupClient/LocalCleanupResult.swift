import Foundation

public struct LocalCleanupResult: Sendable, Equatable {
    public var text: String
    public var chunkCount: Int
    public var promptTokens: Int
    public var generatedTokens: Int
    /// Below `generatedTokens` when prompt-lookup drafts are accepted.
    public var forwardPasses: Int
    public var elapsed: Duration

    public init(text: String, chunkCount: Int, promptTokens: Int, generatedTokens: Int, forwardPasses: Int, elapsed: Duration) {
        self.text = text
        self.chunkCount = chunkCount
        self.promptTokens = promptTokens
        self.generatedTokens = generatedTokens
        self.forwardPasses = forwardPasses
        self.elapsed = elapsed
    }
}
