import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import Shared

actor LocalCleanupRuntime {
    private var container: ModelContainer?
    private var loadedDirectory: URL?
    private var loadTask: Task<ModelContainer, any Error>?
    /// Increments on unload so a load that finishes afterward does not keep the weights resident.
    private var generation = 0

    func prepare(directory: URL?) async throws -> ModelContainer {
        guard let directory else { throw LocalCleanupError.notDownloaded }
        if loadedDirectory != directory { unload() }
        if let container { return container }
        if let loadTask { return try await loadTask.value }

        let loadGeneration = generation
        loadedDirectory = directory
        let task = Task {
            try await LLMModelFactory.shared.loadContainer(from: directory, using: CleanupTokenizerLoader())
        }
        loadTask = task
        let loaded: ModelContainer
        do {
            loaded = try await task.value
        } catch {
            if generation == loadGeneration {
                loadTask = nil
                loadedDirectory = nil
            }
            throw error
        }
        guard generation == loadGeneration else { return loaded }
        loadTask = nil
        container = loaded
        return loaded
    }

    func clean(_ transcript: String, model: CleanupModel, controls: S1MiniControls, directory: URL?) async throws -> LocalCleanupResult {
        let container = try await prepare(directory: directory)
        let request = Request(transcript: transcript, model: model, controls: controls)
        return try await container.perform(values: request) { context, request in
            try Self.generate(request, context: context)
        }
    }

    func unload() {
        generation += 1
        loadTask?.cancel()
        loadTask = nil
        loadedDirectory = nil
        container = nil
        MLX.Memory.clearCache()
    }

    private struct Request: Sendable {
        var transcript: String
        var model: CleanupModel
        var controls: S1MiniControls
    }

    private static func generate(_ request: Request, context: ModelContext) throws -> LocalCleanupResult {
        let start = ContinuousClock.now
        let tokenizer = context.tokenizer
        let stopTokens = Set(["<|im_end|>", "<|endoftext|>"].compactMap(tokenizer.convertTokenToId))
        guard !stopTokens.isEmpty else { throw LocalCleanupError.missingStopToken }

        let chunks = CleanupChunker().chunks(request.transcript) {
            tokenizer.encode(text: $0, addSpecialTokens: false).count
        }
        var outputs: [String] = []
        var promptTokens = 0
        var generatedTokens = 0
        var forwardPasses = 0

        for chunk in chunks {
            try Task.checkCancellation()
            let prompt = tokenizer.encode(
                text: LocalCleanupPrompt.text(model: request.model, transcript: chunk, controls: request.controls),
                addSpecialTokens: false
            )
            let decoded = try PromptLookupDecoder(model: context.model, stopTokens: stopTokens)
                .decode(prompt: prompt, maxTokens: LocalCleanupPrompt.maxOutputTokens(promptTokens: prompt.count))
            let generated = decoded.tokens
            forwardPasses += decoded.forwardPasses
            promptTokens += prompt.count
            generatedTokens += generated.count
            let output = tokenizer.decode(tokenIds: generated, skipSpecialTokens: true)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            outputs.append(output.isEmpty && !CleanupChunker.canBeFillerOnly(chunk) ? chunk : output)
        }

        return LocalCleanupResult(
            text: CleanupChunker.join(outputs),
            chunkCount: chunks.count,
            promptTokens: promptTokens,
            generatedTokens: generatedTokens,
            forwardPasses: forwardPasses,
            elapsed: ContinuousClock.now - start
        )
    }
}
