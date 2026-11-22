import Foundation
import Dependencies
import LogClient
import MLX
import MLXLLM
import MLXLMCommon

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

    func clean(_ transcript: String, directory: URL?) async throws -> String {
        let container = try await prepare(directory: directory)
        return try await container.perform(values: transcript) { context, transcript in
            try Self.generate(transcript, context: context)
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

    private static func generate(_ transcript: String, context: ModelContext) throws -> String {
        let start = ContinuousClock.now
        let tokenizer = context.tokenizer
        let stopTokens = Set(["<|im_end|>", "<|endoftext|>"].compactMap(tokenizer.convertTokenToId))
        guard !stopTokens.isEmpty else { throw LocalCleanupError.missingStopToken }

        let chunks = CleanupChunker().chunks(transcript) {
            tokenizer.encode(text: $0, addSpecialTokens: false).count
        }
        var outputs: [String] = []
        var promptTokens = 0
        var generatedTokens = 0

        for chunk in chunks {
            try Task.checkCancellation()
            let prompt = tokenizer.encode(
                text: LocalCleanupPrompt.text(transcript: chunk),
                addSpecialTokens: false
            )
            let generated = try PromptLookupDecoder(model: context.model, stopTokens: stopTokens)
                .decode(prompt: prompt, maxTokens: LocalCleanupPrompt.maxOutputTokens(promptTokens: prompt.count))
            promptTokens += prompt.count
            generatedTokens += generated.count
            let output = tokenizer.decode(tokenIds: generated, skipSpecialTokens: true)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            outputs.append(output.isEmpty && !CleanupChunker.canBeFillerOnly(chunk) ? chunk : output)
        }

        @Dependency(\.logClient) var log
        log.debug(
            "LocalCleanupClient",
            "chunks=\(chunks.count) promptTokens=\(promptTokens) generatedTokens=\(generatedTokens) modelElapsed=\(ContinuousClock.now - start)"
        )
        return CleanupChunker.join(outputs)
    }
}
