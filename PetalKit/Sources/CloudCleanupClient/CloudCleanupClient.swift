import Dependencies
import DependenciesMacros
import Foundation
import Shared

@DependencyClient
public struct CloudCleanupClient: Sendable {
    public var clean: @Sendable (_ transcript: String, _ configuration: CloudCleanupConfiguration) async throws -> CloudCleanupResult
    public var verifyKey: @Sendable (_ connection: CloudConnection) async throws -> Void
    public var availableModels: @Sendable (_ connection: CloudConnection) async throws -> IdentifiedArrayOf<CloudModel>
    public var checkModel: @Sendable (_ configuration: CloudCleanupConfiguration) async throws -> Void
}

extension CloudCleanupClient: DependencyKey {
    public static var liveValue: Self {
        let session = URLSession(configuration: .ephemeral)
        let runtime = CloudCleanupRuntime(send: { try await session.data(for: $0) })
        return Self(
            clean: { transcript, configuration in
                let start = ContinuousClock.now
                var result = try await runtime.clean(transcript, configuration: configuration)
                result.elapsed = .now - start
                return result
            },
            verifyKey: { try await runtime.verifyKey($0) },
            availableModels: { try await runtime.availableModels($0) },
            checkModel: { try await runtime.checkModel($0) }
        )
    }

    public static var previewValue: Self {
        Self(
            clean: { _, configuration in
                return CloudCleanupResult(
                    text: "So, can you send the report to Sam by Thursday?",
                    model: configuration.model,
                    elapsed: .milliseconds(600)
                )
            },
            verifyKey: { _ in },
            availableModels: { _ in [CloudModel(id: "llama3.2"), CloudModel(id: "qwen3:8b")] },
            checkModel: { _ in }
        )
    }

    public static var testValue: Self { Self() }
}

public extension DependencyValues {
    var cloudCleanupClient: CloudCleanupClient {
        get { self[CloudCleanupClient.self] }
        set { self[CloudCleanupClient.self] = newValue }
    }
}
