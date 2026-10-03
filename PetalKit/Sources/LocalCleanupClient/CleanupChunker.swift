import Foundation
import NaturalLanguage

/// Splits long transcripts into passes of about 1,000 tokens.
/// Chunks break at sentence ends first, then at word boundaries for unpunctuated ASR output.
public struct CleanupChunker: Sendable {
    public var maxTokens: Int

    public init(maxTokens: Int = 768) {
        self.maxTokens = maxTokens
    }

    public func chunks(_ text: String, tokenCount: (String) -> Int) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard tokenCount(trimmed) > maxTokens else { return [trimmed] }

        var chunks: [String] = []
        var current: [String] = []
        var currentTokens = 0

        func flush() {
            guard !current.isEmpty else { return }
            chunks.append(current.joined(separator: " "))
            current = []
            currentTokens = 0
        }

        for piece in pieces(trimmed, tokenCount: tokenCount) {
            if currentTokens + piece.tokens > maxTokens { flush() }
            current.append(piece.text)
            currentTokens += piece.tokens
        }
        flush()
        return chunks
    }

    /// The model returns an empty string for filler-only input. For longer input, an empty result is a failure, and the
    /// raw chunk is safer than dropped dictation.
    public static func canBeFillerOnly(_ chunk: String) -> Bool {
        chunk.split(whereSeparator: \.isWhitespace).count <= 12
    }

    public static func join(_ outputs: [String]) -> String {
        outputs
            .filter { !$0.isEmpty }
            .reduce(into: "") { result, output in
                guard !result.isEmpty else {
                    result = output
                    return
                }
                let isBlock = result.contains("\n") || output.contains("\n")
                result += isBlock ? "\n\n" + output : " " + output
            }
    }

    private func pieces(_ text: String, tokenCount: (String) -> Int) -> [(text: String, tokens: Int)] {
        sentences(text).flatMap { sentence -> [(text: String, tokens: Int)] in
            let tokens = tokenCount(sentence)
            guard tokens > maxTokens else { return [(sentence, tokens)] }
            return sentence
                .split(whereSeparator: \.isWhitespace)
                .map { word in (String(word), tokenCount(" " + word)) }
        }
    }

    private func sentences(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex..<text.endIndex)
            .map { text[$0].trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
