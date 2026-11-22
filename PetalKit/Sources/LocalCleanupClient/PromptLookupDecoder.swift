import MLX
import MLXLMCommon

struct PromptLookupDecoder {
    let model: any LanguageModel
    let stopTokens: Set<Int>
    private let maxDraftTokens = 8
    private let maxNGram = 3
    /// Single-token matches are mostly rejected, and a rejected round costs more than a plain step.
    private let minNGram = 2

    // Short prompts run faster with plain decoding because it overlaps GPU and CPU work.
    private let speculationMinPromptTokens = 320

    private static let prefill = PrefillParameters(stepSize: 1024)

    func decode(prompt: [Int], maxTokens: Int) throws -> [Int] {
        prompt.count < speculationMinPromptTokens
            ? try decodePlain(prompt: prompt, maxTokens: maxTokens)
            : try decodeSpeculative(prompt: prompt, maxTokens: maxTokens)
    }

    private func decodePlain(prompt: [Int], maxTokens: Int) throws -> [Int] {
        var iterator = try TokenIterator(
            input: LMInput(tokens: MLXArray(prompt)),
            model: model,
            processor: nil,
            sampler: ArgMaxSampler(),
            prefill: Self.prefill,
            maxTokens: maxTokens
        )
        var generated: [Int] = []
        while let token = iterator.next(), !stopTokens.contains(token) {
            generated.append(token)
            if generated.count.isMultiple(of: 32) { try Task.checkCancellation() }
        }
        return generated
    }

    private func decodeSpeculative(prompt: [Int], maxTokens: Int) throws -> [Int] {
        let cache = try model.newCache(parameters: nil)
        var next: Int
        switch try model.prepare(LMInput(tokens: MLXArray(prompt)), cache: cache, state: nil, prefill: Self.prefill) {
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

            var accepted = 0
            while accepted < draft.count, predicted[accepted] == draft[accepted], !stopTokens.contains(draft[accepted]) {
                accepted += 1
            }
            generated += draft.prefix(accepted)
            history += draft.prefix(accepted)
            _ = trimPromptCache(cache, numTokens: draft.count - accepted)
            next = predicted[accepted]
        }
        return generated
    }

    private func greedy(_ logits: MLXArray) -> [Int] {
        argMax(logits[0], axis: -1).asArray(Int.self)
    }

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
