import MLX
import MLXLMCommon

/// Greedy decoding with prompt-lookup speculation. Cleaned text mostly copies the transcript, so the next tokens
/// usually already appear in the prompt. Each round drafts them from the prompt and verifies all of them in one
/// forward pass. Verification keeps only tokens that plain greedy decoding also picks.
///
/// A verify round must wait for the GPU, but plain decoding overlaps graph building with GPU work. On an M4 Pro,
/// speculation is 1.5x faster for full 768-token chunks and 20% slower for typical short dictation.
struct S1MiniPromptLookupDecoder {
    let model: any LanguageModel
    let stopTokens: Set<Int>
    var maxDraftTokens = 8
    var maxNGram = 3
    /// Single-token matches are mostly rejected, and a rejected round costs more than a plain step.
    var minNGram = 2

    var speculationMinPromptTokens = 320

    func decode(prompt: [Int], maxTokens: Int) throws -> (tokens: [Int], forwardPasses: Int) {
        prompt.count < speculationMinPromptTokens
            ? try decodePlain(prompt: prompt, maxTokens: maxTokens)
            : try decodeSpeculative(prompt: prompt, maxTokens: maxTokens)
    }

    private func decodePlain(prompt: [Int], maxTokens: Int) throws -> (tokens: [Int], forwardPasses: Int) {
        var iterator = try TokenIterator(
            input: LMInput(tokens: MLXArray(prompt)),
            model: model,
            processor: nil,
            sampler: ArgMaxSampler(),
            prefillStepSize: 1024,
            maxTokens: maxTokens
        )
        var generated: [Int] = []
        while let token = iterator.next(), !stopTokens.contains(token) {
            generated.append(token)
            if generated.count.isMultiple(of: 32) { try Task.checkCancellation() }
        }
        return (generated, generated.count + 1)
    }

    private func decodeSpeculative(prompt: [Int], maxTokens: Int) throws -> (tokens: [Int], forwardPasses: Int) {
        let cache = model.newCache(parameters: nil)
        var next: Int
        var forwardPasses = 1
        switch try model.prepare(LMInput(tokens: MLXArray(prompt)), cache: cache, windowSize: 1024) {
        case let .tokens(remaining):
            next = greedy(model(remaining[text: .newAxis], cache: cache, state: nil).logits[0..., (-1)..., 0...])[0]
        case let .logits(output):
            next = greedy(output.logits[0..., (-1)..., 0...])[0]
        }

        var history = prompt
        var generated: [Int] = []
        while generated.count < maxTokens, !stopTokens.contains(next) {
            try Task.checkCancellation()
            generated.append(next)
            history.append(next)

            let draft = draftTokens(history: history, limit: min(maxDraftTokens, maxTokens - generated.count))
            let verify = LMInput.Text(tokens: MLXArray([next] + draft))
            let predicted = greedy(model(verify[text: .newAxis], cache: cache, state: nil).logits)
            forwardPasses += 1

            var accepted = 0
            while accepted < draft.count, predicted[accepted] == draft[accepted], !stopTokens.contains(draft[accepted]) {
                accepted += 1
            }
            generated += draft.prefix(accepted)
            history += draft.prefix(accepted)
            _ = trimPromptCache(cache, numTokens: draft.count - accepted)
            next = predicted[accepted]
        }
        return (Array(generated.prefix(maxTokens)), forwardPasses)
    }

    private func greedy(_ logits: MLXArray) -> [Int] {
        argMax(logits[0], axis: -1).asArray(Int.self)
    }

    /// Finds the latest earlier occurrence of the history's final n-gram and proposes what followed it.
    private func draftTokens(history: [Int], limit: Int) -> [Int] {
        guard limit > 0 else { return [] }
        for n in stride(from: min(maxNGram, history.count - 1), through: minNGram, by: -1) {
            let suffix = history[(history.count - n)...]
            var start = history.count - n - 1
            while start >= 0 {
                if history[start ..< (start + n)].elementsEqual(suffix) {
                    let continuation = history[(start + n) ..< min(start + n + limit, history.count)]
                    if !continuation.isEmpty { return Array(continuation) }
                }
                start -= 1
            }
        }
        return []
    }
}
