import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import Shared

actor S1MiniRuntime {
    private var container: ModelContainer?
    private var loadTask: Task<ModelContainer, any Error>?
    /// Increments on unload so a load that finishes afterward does not keep the weights resident.
    private var generation = 0

    func prepare(directory: URL? = S1MiniModelFiles.directory) async throws -> ModelContainer {
        if let container { return container }
        if let loadTask { return try await loadTask.value }
        guard let directory else { throw S1MiniError.notDownloaded }

        let loadGeneration = generation
        let task = Task {
            try await LLMModelFactory.shared.loadContainer(from: directory, using: S1MiniTokenizerLoader())
        }
        loadTask = task
        let loaded: ModelContainer
        do {
            loaded = try await task.value
        } catch {
            if generation == loadGeneration { loadTask = nil }
            throw error
        }
        guard generation == loadGeneration else { return loaded }
        loadTask = nil
        container = loaded
        return loaded
    }

    func clean(_ transcript: String, controls: S1MiniControls, directory: URL? = S1MiniModelFiles.directory) async throws -> S1MiniCleanup {
        let container = try await prepare(directory: directory)
        return try await container.perform(values: Request(transcript: transcript, controls: controls)) { context, request in
            try Self.generate(request, context: context)
        }
    }

    func unload() {
        generation += 1
        loadTask?.cancel()
        loadTask = nil
        container = nil
        MLX.Memory.clearCache()
    }

    private struct Request: Sendable {
        var transcript: String
        var controls: S1MiniControls
    }

    private static func generate(_ request: Request, context: ModelContext) throws -> S1MiniCleanup {
        let start = ContinuousClock.now
        let tokenizer = context.tokenizer
        let stopTokens = Set(["<|im_end|>", "<|endoftext|>"].compactMap(tokenizer.convertTokenToId))
        guard !stopTokens.isEmpty else { throw S1MiniError.missingStopToken }

        let chunks = S1MiniChunker().chunks(request.transcript) {
            tokenizer.encode(text: $0, addSpecialTokens: false).count
        }
        var outputs: [String] = []
        var promptTokens = 0
        var generatedTokens = 0
        var forwardPasses = 0

        for chunk in chunks {
            try Task.checkCancellation()
            let prompt = tokenizer.encode(
                text: S1MiniPrompt.text(transcript: chunk, controls: request.controls),
                addSpecialTokens: false
            )
            let decoded = try S1MiniPromptLookupDecoder(model: context.model, stopTokens: stopTokens)
                .decode(prompt: prompt, maxTokens: S1MiniPrompt.maxOutputTokens(promptTokens: prompt.count))
            let generated = decoded.tokens
            forwardPasses += decoded.forwardPasses
            promptTokens += prompt.count
            generatedTokens += generated.count
            let output = tokenizer.decode(tokenIds: generated, skipSpecialTokens: true)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            outputs.append(output.isEmpty && !S1MiniChunker.canBeFillerOnly(chunk) ? chunk : output)
        }

        return S1MiniCleanup(
            text: S1MiniChunker.join(outputs),
            chunkCount: chunks.count,
            promptTokens: promptTokens,
            generatedTokens: generatedTokens,
            forwardPasses: forwardPasses,
            elapsed: ContinuousClock.now - start
        )
    }
}
