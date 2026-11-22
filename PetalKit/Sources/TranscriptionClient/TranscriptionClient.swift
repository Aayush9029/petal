import AVFoundation
import Dependencies
import DependenciesMacros
import Foundation
import LogClient
import MLXClient
import Shared

public enum TranscriptionStage: Equatable, Sendable {
    case trimming
    case speeding
    case transcribing
    case refining
}

@DependencyClient
public struct TranscriptionClient: Sendable {
    public var prepareModelIfNeeded: @Sendable (ModelOption) async throws -> Void
    public var importAudio: @Sendable (_ source: URL, _ destination: URL) async throws -> Void
    public var transcribe: @Sendable (URL, ModelOption, @escaping @Sendable (TranscriptionStage) async -> Void) async throws -> String
    public var transcribeStream: @Sendable (AudioSampleStream, ModelOption, @escaping @Sendable (String) async -> Void) async throws -> String
    public var unloadModel: @Sendable () async -> Void
    public var audioDurationSeconds: @Sendable (URL) -> Double = { _ in 0 }

    public func transcribe(_ url: URL, _ model: ModelOption) async throws -> String {
        try await transcribe(url, model) { _ in }
    }

}

extension TranscriptionClient: DependencyKey {
    public static var liveValue: Self {
        Self(
            prepareModelIfNeeded: { option in
                guard option.requiresDownload else { return }
                @Dependency(\.mlxClient) var mlx
                try await mlx.prepareModelIfNeeded(option)
            },
            importAudio: { try await TranscriptionAudio.importFile(from: $0, to: $1) },
            transcribe: { url, model, stage in
                @Dependency(\.logClient) var log
                @SharedReader(.trimSilenceEnabled) var trim
                @SharedReader(.autoSpeedEnabled) var autoSpeed
                let start = ContinuousClock.now
                do {
                    guard let input = try await TranscriptionAudio.prepare(url, trim: trim, autoSpeed: autoSpeed, onStage: stage) else {
                        return ""
                    }
                    defer {
                        if input != url { try? FileManager.default.removeItem(at: input) }
                    }
                    try Task.checkCancellation()
                    await stage(.transcribing)
                    let text: String
                    if model == .appleSpeech {
                        guard #available(macOS 26, *) else { throw AppleSpeechError.unavailable }
                        text = try await AppleSpeechRuntime.transcribe(audioURL: input)
                    } else {
                        @Dependency(\.mlxClient) var mlx
                        text = try await mlx.transcribe(input, model)
                    }
                    log.debug("TranscriptionClient", "\(model.rawValue) transcribed \(url.lastPathComponent) in \(start.duration(to: .now)) (\(text.count) characters).")
                    return text
                } catch {
                    log.error("TranscriptionClient", "\(model.rawValue) failed to transcribe \(url.lastPathComponent): \(error.localizedDescription)")
                    throw error
                }
            },
            transcribeStream: { audio, model, partial in
                guard model.supportsStreamingTranscription else { throw StreamingUnsupportedError(model: model) }
                @Dependency(\.mlxClient) var mlx
                return try await mlx.transcribeStream(audio, model, partial)
            },
            unloadModel: {
                @Dependency(\.mlxClient) var mlx
                await mlx.unloadModel()
            },
            audioDurationSeconds: { url in
                guard let file = try? AVAudioFile(forReading: url), file.fileFormat.sampleRate > 0 else { return 0 }
                return Double(file.length) / file.fileFormat.sampleRate
            }
        )
    }

    public static let testValue = Self()
}

public extension DependencyValues {
    var transcriptionClient: TranscriptionClient {
        get { self[TranscriptionClient.self] }
        set { self[TranscriptionClient.self] = newValue }
    }
}

private struct StreamingUnsupportedError: LocalizedError {
    let model: ModelOption
    var errorDescription: String? { "\(model.displayName) does not support live transcription." }
}
