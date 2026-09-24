import Foundation
import MLXLMCommon
import Tokenizers

struct CleanupTokenizerLoader: TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        CleanupTokenizer(upstream: try await AutoTokenizer.from(modelFolder: directory))
    }
}
