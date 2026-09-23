import Foundation
import MLXLMCommon
import Tokenizers

struct S1MiniTokenizerLoader: TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        S1MiniTokenizer(upstream: try await AutoTokenizer.from(modelFolder: directory))
    }
}
