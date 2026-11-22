import Dependencies
import DependenciesMacros
import Foundation
import Shared

@DependencyClient
public struct MLXClient: Sendable {
    public var prepareModelIfNeeded: @Sendable (ModelOption) async throws -> Void
    public var transcribe: @Sendable (URL, ModelOption) async throws -> String
    public var transcribeStream: @Sendable (AudioSampleStream, ModelOption, @escaping @Sendable (String) async -> Void) async throws -> String
    public var unloadModel: @Sendable () async -> Void
}

extension MLXClient: DependencyKey {
    public static var liveValue: Self {
        let runtime = SpeechModelCache()
        return Self(
            prepareModelIfNeeded: { _ = try await runtime.engine(for: $0) },
            transcribe: { url, model in
                let engine = try await runtime.engine(for: model)
                try Task.checkCancellation()
                return try await engine.transcribe(url)
            },
            transcribeStream: { audio, model, partial in
                let engine = try await runtime.engine(for: model)
                try Task.checkCancellation()
                return try await engine.transcribe(audio, onPartial: partial)
            },
            unloadModel: { await runtime.unload() }
        )
    }

    public static let testValue = Self()
}

public extension DependencyValues {
    var mlxClient: MLXClient {
        get { self[MLXClient.self] }
        set { self[MLXClient.self] = newValue }
    }
}

private actor SpeechModelCache {
    private var current: (model: ModelOption, task: Task<SpeechEngine, Error>)?

    private var preparationFinished: Task<Void, Never>?

    func engine(for model: ModelOption) async throws -> SpeechEngine {
        if let current, current.model == model { return try await current.task.value }

        let previous = preparationFinished
        let task = Task {
            await previous?.value
            return try await SpeechEngine(model: model)
        }
        // Serializing loads bounds peak memory when the user switches between large models.
        preparationFinished = Task { _ = await task.result }
        current = (model, task)
        do {
            return try await task.value
        } catch {
            if current?.task == task { current = nil }
            throw error
        }
    }

    func unload() {
        current = nil
    }
}
