import AVFoundation
import Dependencies
import DownloadClient
import FluidAudio
import Foundation
import LogClient
import MLX
import MLXAudioCore
import MLXAudioSTT
import Shared
import Sharing
import WhisperKit

actor SpeechEngine {
    private enum Backend {
        case voxtral(VoxtralRealtimeModel)
        case qwen(Qwen3ASRModel)
        case unified(StreamingUnifiedAsrManager)
        case parakeet(AsrManager)
        case whisper(WhisperKit)
    }

    private let backend: Backend
    private let supportsSpokenLanguageChoice: Bool
    private var isStreaming = false

    init(model: ModelOption) async throws {
        self.supportsSpokenLanguageChoice = model.supportsSpokenLanguageChoice
        @Dependency(\.downloadClient) var downloads
        @Dependency(\.logClient) var log
        let start = ContinuousClock.now
        guard let files = SpeechModelFiles(model), let directory = downloads.modelDirectoryURL(model) else {
            throw EngineError.unavailable(model)
        }

        switch files {
        case .qwen:
            let qwen = try await Qwen3ASRModel.fromModelDirectory(directory)
            _ = qwen.generate(audio: Self.warmupAudio)
            backend = .qwen(qwen)
        case .voxtral:
            let voxtral = try VoxtralRealtimeModel.fromDirectory(directory)
            _ = voxtral.generate(audio: Self.warmupAudio)
            backend = .voxtral(voxtral)
        case let .unified(artifacts):
            let manager = artifacts.makeManager()
            try await manager.loadModels(from: directory)
            backend = .unified(manager)
        case let .parakeet(version):
            // FluidAudio's remote loader also fetches an optional CTC head.
            let models = try AsrModels.loadLocal(from: directory, version: version)
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            backend = .parakeet(manager)
        case .whisperKit:
            backend = .whisper(try await Self.loadWhisper(from: directory))
        }
        log.debug("MLXClient", "Prepared \(model.rawValue) in \(start.duration(to: .now)).")
    }

    private static func loadWhisper(from directory: URL) async throws -> WhisperKit {
        guard let source = SpeechModelFiles.whisperTokenizerDirectory(in: directory) else {
            throw EngineError.unavailable(.whisperLargeV3Turbo)
        }
        // WhisperKit falls back to the Hub on a tokenizer read or parse failure.
        // Validate a private copy so uninstalling the model cannot race its second read.
        let snapshot = URL.temporaryDirectory.appending(component: UUID().uuidString)
        let files = FileManager.default
        try files.createDirectory(at: snapshot, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: snapshot) }
        for name in ["tokenizer.json", "tokenizer_config.json", "config.json"] {
            let file = source.appending(component: name)
            if files.fileExists(atPath: file.path) {
                try files.copyItem(at: file, to: snapshot.appending(component: name))
            }
        }
        _ = try await AutoTokenizerWrapper.from(modelFolder: snapshot)
        return try await WhisperKit(modelFolder: directory.path, tokenizerFolder: snapshot, download: false)
    }

    // MLX compiles kernels lazily on first inference.
    private static var warmupAudio: MLXArray { MLXArray.zeros([speechSampleRate], dtype: .float32) }

    private var language: SpokenLanguage? {
        @SharedReader(.spokenLanguageCode) var code
        return SpokenLanguage(rawValue: code)
    }

    func transcribe(_ url: URL) async throws -> String {
        switch backend {
        case let .voxtral(model):
            let (_, audio) = try loadAudioArray(from: url, sampleRate: speechSampleRate)
            return model.generate(audio: audio).text.trimmingCharacters(in: .whitespacesAndNewlines)
        case let .qwen(model):
            let (_, audio) = try loadAudioArray(from: url, sampleRate: speechSampleRate)
            // The default 20-minute context hallucinates repetitions on long recordings.
            let spokenLanguage = supportsSpokenLanguageChoice ? language?.name : "English"
            let result = model.generate(audio: audio, language: spokenLanguage, chunkDuration: 30)
            return result.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        case .unified:
            let reader = try AudioFileSampleReader(samples: AudioConverter().resampleAudioFile(url))
            return try await transcribe(AudioSampleStream(unfolding: { await reader.next() }), onPartial: { _ in })
        case let .parakeet(manager):
            var state = try TdtDecoderState(decoderLayers: await manager.decoderLayerCount)
            let result = try await manager.transcribe(url, decoderState: &state)
            return result.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        case let .whisper(whisper):
            // Without language detection WhisperKit prefills the English token and translates speech.
            let language = language
            let options = DecodingOptions(language: language?.code, detectLanguage: language == nil)
            nonisolated(unsafe) let instance = whisper
            let results = try await instance.transcribe(audioPath: url.path, decodeOptions: options)
            return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func transcribe(
        _ audio: AudioSampleStream, onPartial: @escaping @Sendable (String) async -> Void
    ) async throws -> String {
        guard case let .unified(manager) = backend, !isStreaming else { throw EngineError.streamUnavailable }
        isStreaming = true
        defer { isStreaming = false }
        do {
            try await manager.reset()
            var previous = ""
            for try await samples in audio {
                try Task.checkCancellation()
                guard !samples.isEmpty else { continue }
                try await manager.appendAudio(Self.pcmBuffer(samples))
                try await manager.processBufferedAudio()
                _ = await manager.consumeTokenTimings()
                let partial = await manager.getPartialTranscript()
                if previous != partial {
                    previous = partial
                    await onPartial(partial)
                }
            }
            try Task.checkCancellation()
            let final = try await manager.finish()
            try Task.checkCancellation()
            try await manager.reset()
            return final
        } catch {
            try? await manager.reset()
            throw error
        }
    }

    private static func pcmBuffer(_ samples: [Float]) throws -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(speechSampleRate), channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0]
        else { throw EngineError.streamUnavailable }
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: $0.count) }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        return buffer
    }
}

private enum EngineError: LocalizedError {
    case unavailable(ModelOption)
    case streamUnavailable

    var errorDescription: String? {
        switch self {
        case let .unavailable(model): "\(model.displayName) is unavailable."
        case .streamUnavailable: "Transcription pipeline is not available."
        }
    }
}
