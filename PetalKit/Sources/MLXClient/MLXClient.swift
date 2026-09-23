import AVFoundation
import Dependencies
import DependenciesMacros
import FluidAudio
import Foundation
import LogClient
import Shared
import MLXAudioCore
import MLXAudioSTT
import VoxtralCore
import WhisperKit

/// Root directory for all Petal data: ~/Documents/petal/
private let petalDirectory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    .appendingPathComponent("petal")

public enum MLXModelBackend: String, Sendable, Equatable {
    case voxtral
    case fluidAudio
    case whisperKit
}

public struct MLXModelInfo: Sendable, Equatable {
    public var id: String
    public var repoId: String
    public var name: String
    public var summary: String
    public var size: String?
    public var quantization: String
    public var parameters: String
    public var backend: MLXModelBackend
    public var recommended: Bool

    public init(
        id: String,
        repoId: String,
        name: String,
        summary: String,
        size: String? = nil,
        quantization: String,
        parameters: String,
        backend: MLXModelBackend,
        recommended: Bool
    ) {
        self.id = id
        self.repoId = repoId
        self.name = name
        self.summary = summary
        self.size = size
        self.quantization = quantization
        self.parameters = parameters
        self.backend = backend
        self.recommended = recommended
    }
}

public enum MLXPipelineModel: String, Sendable {
    case mini3b8bit
    case qwen3ASR17B8bit
    case parakeetUnified06B
    case parakeetTDTCTC110M
    case whisperLargeV3Turbo
}

public enum MLXTranscriptionMode: Sendable {
    case verbatim
    case smart(prompt: String)
}

public enum MLXDownloadError: LocalizedError, Sendable, Equatable {
    case paused
    case cancelled
    case aria2BinaryMissing
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .paused:
            return "Download paused"
        case .cancelled:
            return "Download cancelled"
        case .aria2BinaryMissing:
            return "aria2c binary is missing from the app bundle or system PATH."
        case let .failed(message):
            return message
        }
    }
}

@DependencyClient
public struct MLXClient: Sendable {
    public var isModelDownloaded: @Sendable (MLXModelInfo) -> Bool = { _ in false }
    public var downloadModel: @Sendable (MLXModelInfo, @escaping @Sendable (Double, String) -> Void) async throws -> Void
    public var pauseDownload: @Sendable () -> Void = {}
    public var cancelDownload: @Sendable () -> Void = {}
    public var modelDirectoryURL: @Sendable (MLXModelInfo) -> URL? = { _ in nil }
    public var deleteModel: @Sendable (MLXModelInfo) async throws -> Void
    public var prepareModelIfNeeded: @Sendable (MLXPipelineModel) async throws -> Void
    public var transcribe: @Sendable (URL, MLXTranscriptionMode) async throws -> String
    /// Consumes ordered 16 kHz mono PCM until the producer finishes, then flushes the decoder.
    public var transcribeStream: @Sendable (AudioSampleStream, @escaping @Sendable (String) async -> Void) async throws -> String
    public var unloadModel: @Sendable () async -> Void = {}
}

extension MLXClient: DependencyKey {
    public static var liveValue: Self {
        let runtime = LiveMLXRuntime()
        return Self(
            isModelDownloaded: { info in
                switch info.backend {
                case .voxtral:
                    return ModelDownloader.findModelPath(for: info.voxtralModelInfo) != nil
                case .fluidAudio:
                    return FluidAudioCache.isModelDownloaded(info: info)
                case .whisperKit:
                    return WhisperKitCache.isModelDownloaded(variant: info.id)
                }
            },
            downloadModel: { info, progress in
                do {
                    switch info.backend {
                    case .voxtral:
                        _ = try await ModelDownloader.download(info.voxtralModelInfo, progress: progress)
                    case .fluidAudio:
                        try await FluidAudioCache.downloadIfNeeded(info: info, progress: progress)
                    case .whisperKit:
                        try await WhisperKitCache.downloadIfNeeded(variant: info.id, progress: progress)
                    }
                } catch {
                    throw normalizeDownloadError(error)
                }
            },
            pauseDownload: {
                ModelDownloader.pauseDownload()
            },
            cancelDownload: {
                ModelDownloader.cancelDownload()
            },
            modelDirectoryURL: { info in
                switch info.backend {
                case .voxtral:
                    return ModelDownloader.findModelPath(for: info.voxtralModelInfo)
                case .fluidAudio:
                    return FluidAudioCache.modelDirectoryURL(info: info)
                case .whisperKit:
                    return WhisperKitCache.modelDirectoryURL(variant: info.id)
                }
            },
            deleteModel: { info in
                switch info.backend {
                case .voxtral:
                    if let path = ModelDownloader.findModelPath(for: info.voxtralModelInfo) {
                        try FileManager.default.removeItem(at: path)
                    }
                case .fluidAudio:
                    try FluidAudioCache.deleteModel(info: info)
                case .whisperKit:
                    try WhisperKitCache.deleteModel(variant: info.id)
                }
            },
            prepareModelIfNeeded: { model in
                @Dependency(\.logClient) var logClient
                let requestID = UUID().uuidString
                let startUptime = ProcessInfo.processInfo.systemUptime
                logClient.debug(
                    "MLXClient",
                    "Prepare requested. requestID=\(requestID), model=\(model.rawValue)"
                )
                do {
                    try await runtime.prepareModelIfNeeded(model: model) { message in
                        logClient.debug("MLXClient", "[prepare \(requestID)] \(message)")
                    }
                    let elapsed = ProcessInfo.processInfo.systemUptime - startUptime
                    logClient.debug(
                        "MLXClient",
                        "Prepare completed. requestID=\(requestID), model=\(model.rawValue), elapsed=\(formatElapsedSeconds(elapsed))"
                    )
                } catch {
                    let elapsed = ProcessInfo.processInfo.systemUptime - startUptime
                    logClient.error(
                        "MLXClient",
                        "Prepare failed. requestID=\(requestID), model=\(model.rawValue), elapsed=\(formatElapsedSeconds(elapsed)), error=\(error.localizedDescription)"
                    )
                    throw error
                }
            },
            transcribe: { audioURL, mode in
                @Dependency(\.logClient) var logClient
                let requestID = UUID().uuidString
                let startUptime = ProcessInfo.processInfo.systemUptime
                logClient.debug(
                    "MLXClient",
                    "Transcribe requested. requestID=\(requestID), audioFile=\(audioURL.lastPathComponent), mode=\(mode.logSummary)"
                )
                do {
                    let text = try await runtime.transcribe(audioURL: audioURL, mode: mode) { message in
                        logClient.debug("MLXClient", "[transcribe \(requestID)] \(message)")
                    }
                    let elapsed = ProcessInfo.processInfo.systemUptime - startUptime
                    logClient.debug(
                        "MLXClient",
                        "Transcribe completed. requestID=\(requestID), chars=\(text.count), elapsed=\(formatElapsedSeconds(elapsed))"
                    )
                    return text
                } catch {
                    let elapsed = ProcessInfo.processInfo.systemUptime - startUptime
                    logClient.error(
                        "MLXClient",
                        "Transcribe failed. requestID=\(requestID), elapsed=\(formatElapsedSeconds(elapsed)), mode=\(mode.logSummary), error=\(error.localizedDescription)"
                    )
                    throw error
                }
            },
            transcribeStream: { audio, partial in
                try await runtime.transcribeStream(audio, onPartial: partial)
            },
            unloadModel: {
                await runtime.unloadModel()
            }
        )
    }
}

extension MLXClient: TestDependencyKey {
    public static var testValue: Self {
        Self(
            isModelDownloaded: { _ in false },
            downloadModel: { _, _ in },
            pauseDownload: {},
            cancelDownload: {},
            modelDirectoryURL: { _ in nil },
            deleteModel: { _ in },
            prepareModelIfNeeded: { _ in },
            transcribe: { _, _ in "Test transcription" },
            transcribeStream: { _, _ in "Test transcription" },
            unloadModel: {}
        )
    }
}

public extension DependencyValues {
    var mlxClient: MLXClient {
        get { self[MLXClient.self] }
        set { self[MLXClient.self] = newValue }
    }
}

private actor LiveMLXRuntime {
    private let audioConverter = AudioConverter()

    private var loadedModel: MLXPipelineModel?
    private var voxtralRealtimeModel: VoxtralRealtimeModel?
    private var qwen3AsrModel: Qwen3ASRModel?
    private var parakeetAsrManager: AsrManager?
    private var whisperKitInstance: WhisperKit?
    private var unifiedAsrManager: StreamingUnifiedAsrManager?
    private var isStreaming = false

    func prepareModelIfNeeded(
        model: MLXPipelineModel,
        log: @Sendable (String) -> Void
    ) async throws {
        let prepareStart = ProcessInfo.processInfo.systemUptime
        log("prepare.enter model=\(model.rawValue), loadedModel=\(loadedModel?.rawValue ?? "none")")

        if loadedModel == model {
            log("prepare.skip reason=already-loaded")
            return
        }

        let unloadStart = ProcessInfo.processInfo.systemUptime
        unloadModel()
        let unloadElapsed = ProcessInfo.processInfo.systemUptime - unloadStart
        log("prepare.unload.completed elapsed=\(formatElapsedSeconds(unloadElapsed))")

        switch model {
        case .mini3b8bit:
            guard let info = model.voxtralRealtimeModelInfo,
                  let modelDirectory = ModelDownloader.findModelPath(for: info)
            else {
                throw MLXError.invalidModelIdentifier(model.rawValue)
            }
            log("prepare.voxtral-realtime.begin model=\(model.rawValue)")
            let loadStart = ProcessInfo.processInfo.systemUptime
            voxtralRealtimeModel = try VoxtralRealtimeModel.fromDirectory(modelDirectory)
            let loadElapsed = ProcessInfo.processInfo.systemUptime - loadStart
            log("prepare.voxtral-realtime.loaded elapsed=\(formatElapsedSeconds(loadElapsed))")

        case .qwen3ASR17B8bit:
            guard let info = model.huggingFaceModelInfo,
                  let modelDirectory = ModelDownloader.findModelPath(for: info)
            else {
                throw MLXError.invalidModelIdentifier(model.rawValue)
            }
            let loadStart = ProcessInfo.processInfo.systemUptime
            qwen3AsrModel = try await Qwen3ASRModel.fromModelDirectory(modelDirectory)
            log("prepare.qwen-mlx.loaded elapsed=\(formatElapsedSeconds(ProcessInfo.processInfo.systemUptime - loadStart))")

        case .parakeetUnified06B:
            let directory = try await FluidAudioCache.downloadIfNeeded(model: .parakeetUnified)
            let manager = StreamingUnifiedAsrManager(config: UnifiedModelArtifacts.config)
            try await manager.loadModels(from: directory)
            unifiedAsrManager = manager

        case .parakeetTDTCTC110M:
            guard let fluidAudioModel = model.fluidAudioModel,
                  let version = fluidAudioModel.parakeetVersion
            else {
                throw MLXError.invalidModelIdentifier(model.rawValue)
            }
            log("prepare.parakeet.begin variant=\(model.rawValue)")
            let resolveStart = ProcessInfo.processInfo.systemUptime
            let modelDirectory = try await FluidAudioCache.downloadIfNeeded(model: fluidAudioModel)
            let resolveElapsed = ProcessInfo.processInfo.systemUptime - resolveStart
            log(
                "prepare.parakeet.model-ready elapsed=\(formatElapsedSeconds(resolveElapsed)), directory=\(modelDirectory.lastPathComponent)"
            )
            let asrLoadStart = ProcessInfo.processInfo.systemUptime
            // loadLocal stays offline; load would fetch an optional CTC head from the network.
            let asrModels = try AsrModels.loadLocal(from: modelDirectory, version: version)
            let asrLoadElapsed = ProcessInfo.processInfo.systemUptime - asrLoadStart
            log("prepare.parakeet.asrModels-loaded elapsed=\(formatElapsedSeconds(asrLoadElapsed))")
            let managerInitStart = ProcessInfo.processInfo.systemUptime
            let manager = AsrManager(config: .default)
            try await manager.loadModels(asrModels)
            let managerInitElapsed = ProcessInfo.processInfo.systemUptime - managerInitStart
            log("prepare.parakeet.manager-initialized elapsed=\(formatElapsedSeconds(managerInitElapsed))")
            parakeetAsrManager = manager

        case .whisperLargeV3Turbo:
            guard let variant = model.whisperKitVariant else {
                throw MLXError.invalidModelIdentifier(model.rawValue)
            }
            log("prepare.whisper.begin variant=\(variant)")
            let whisperStart = ProcessInfo.processInfo.systemUptime
            whisperKitInstance = try await WhisperKit(model: variant, downloadBase: petalDirectory)
            let whisperElapsed = ProcessInfo.processInfo.systemUptime - whisperStart
            log("prepare.whisper.loaded elapsed=\(formatElapsedSeconds(whisperElapsed))")
        }

        loadedModel = model
        let prepareElapsed = ProcessInfo.processInfo.systemUptime - prepareStart
        log("prepare.completed model=\(model.rawValue), elapsed=\(formatElapsedSeconds(prepareElapsed))")
    }

    func transcribe(
        audioURL: URL,
        mode: MLXTranscriptionMode,
        log: @Sendable (String) -> Void
    ) async throws -> String {
        guard let loadedModel else {
            throw MLXError.pipelineUnavailable
        }

        let inputDuration = mlxAudioDurationSeconds(audioURL)
        let inputSizeBytes = mlxAudioFileSizeBytes(audioURL) ?? 0
        let totalStart = ProcessInfo.processInfo.systemUptime

        log(
            "transcribe.enter model=\(loadedModel.rawValue), mode=\(mode.logSummary), audioFile=\(audioURL.lastPathComponent), audioDuration=\(formatElapsedSeconds(inputDuration)), audioSizeBytes=\(inputSizeBytes)"
        )

        do {
            let transcript: String

            switch loadedModel {
            case .mini3b8bit:
                guard let voxtralRealtimeModel else {
                    throw MLXError.pipelineUnavailable
                }
                guard case .verbatim = mode else {
                    throw MLXError.invalidModelIdentifier("Voxtral Realtime supports verbatim transcription only.")
                }

                let loadAudioStart = ProcessInfo.processInfo.systemUptime
                let (_, audio) = try loadAudioArray(from: audioURL, sampleRate: 16_000)
                let loadAudioElapsed = ProcessInfo.processInfo.systemUptime - loadAudioStart
                log("transcribe.voxtral-realtime.audio-loaded elapsed=\(formatElapsedSeconds(loadAudioElapsed))")

                let inferenceStart = ProcessInfo.processInfo.systemUptime
                let output = voxtralRealtimeModel.generate(audio: audio)
                let inferenceElapsed = ProcessInfo.processInfo.systemUptime - inferenceStart
                log(
                    "transcribe.voxtral-realtime.inference completed elapsed=\(formatElapsedSeconds(inferenceElapsed)), rawChars=\(output.text.count)"
                )
                let text = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    log("transcribe.voxtral-realtime.empty-output")
                    throw MLXError.pipelineUnavailable
                }
                transcript = text

            case .qwen3ASR17B8bit:
                guard let qwen3AsrModel else {
                    throw MLXError.pipelineUnavailable
                }
                let (_, audio) = try loadAudioArray(from: audioURL, sampleRate: 16_000)
                let inferenceStart = ProcessInfo.processInfo.systemUptime
                let output = qwen3AsrModel.generate(audio: audio)
                log("transcribe.qwen-mlx.inference completed elapsed=\(formatElapsedSeconds(ProcessInfo.processInfo.systemUptime - inferenceStart)), rawChars=\(output.text.count)")
                let normalizedText = normalizeQwenTranscript(output.text)
                guard !normalizedText.isEmpty else {
                    throw MLXError.pipelineUnavailable
                }
                transcript = normalizedText

            case .parakeetUnified06B:
                let samples = try audioConverter.resampleAudioFile(audioURL)
                let reader = AudioFileSampleReader(samples: samples)
                let audio = AudioSampleStream(unfolding: { await reader.next() })
                transcript = try await transcribeStream(audio, onPartial: { _ in })

            case .parakeetTDTCTC110M:
                guard let parakeetAsrManager else {
                    throw MLXError.pipelineUnavailable
                }

                nonisolated(unsafe) let manager = parakeetAsrManager
                let inferenceStart = ProcessInfo.processInfo.systemUptime
                var decoderState = try TdtDecoderState(decoderLayers: await manager.decoderLayerCount)
                let result = try await manager.transcribe(audioURL, decoderState: &decoderState)
                let inferenceElapsed = ProcessInfo.processInfo.systemUptime - inferenceStart
                log(
                    "transcribe.parakeet.inference completed elapsed=\(formatElapsedSeconds(inferenceElapsed)), rawChars=\(result.text.count)"
                )

                let text = normalizeParakeetTranscript(result.text)
                guard !text.isEmpty else {
                    log("transcribe.parakeet.empty-normalized-output")
                    throw MLXError.pipelineUnavailable
                }
                log("transcribe.parakeet.normalized chars=\(text.count)")
                transcript = text

            case .whisperLargeV3Turbo:
                guard let whisperKitInstance else {
                    throw MLXError.pipelineUnavailable
                }
                nonisolated(unsafe) let instance = whisperKitInstance
                let audioPath = audioURL.path
                let whisperStart = ProcessInfo.processInfo.systemUptime
                let results = try await instance.transcribe(audioPath: audioPath)
                let whisperElapsed = ProcessInfo.processInfo.systemUptime - whisperStart
                log(
                    "transcribe.whisper.backend completed elapsed=\(formatElapsedSeconds(whisperElapsed)), segments=\(results.count)"
                )

                let text = results.map(\.text).joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    log("transcribe.whisper.empty-output")
                    throw MLXError.pipelineUnavailable
                }
                transcript = text
            }

            let totalElapsed = ProcessInfo.processInfo.systemUptime - totalStart
            log(
                "transcribe.completed model=\(loadedModel.rawValue), chars=\(transcript.count), elapsed=\(formatElapsedSeconds(totalElapsed))"
            )
            return transcript
        } catch {
            let failedElapsed = ProcessInfo.processInfo.systemUptime - totalStart
            log(
                "transcribe.failed model=\(loadedModel.rawValue), elapsed=\(formatElapsedSeconds(failedElapsed)), error=\(error.localizedDescription)"
            )
            throw error
        }
    }

    /// Upstream FluidAudio accepts streaming input only as a PCM buffer.
    private static func pcmBuffer(_ samples: [Float]) throws -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0]
        else { throw MLXError.pipelineUnavailable }
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        return buffer
    }

    func transcribeStream(
        _ audio: AudioSampleStream, onPartial: @escaping @Sendable (String) async -> Void
    ) async throws -> String {
        guard let manager = unifiedAsrManager, !isStreaming else { throw MLXError.pipelineUnavailable }
        isStreaming = true
        defer { isStreaming = false }
        // Retain this engine for the entire session, even if the selected model changes.
        do {
            try await manager.reset()
            var previousTranscript = ""
            for try await samples in audio {
                try Task.checkCancellation()
                guard !samples.isEmpty else { continue }
                try await manager.appendAudio(Self.pcmBuffer(samples))
                try await manager.processBufferedAudio()
                _ = await manager.consumeTokenTimings()
                let partial = await manager.getPartialTranscript()
                if partial != previousTranscript {
                    previousTranscript = partial
                    await onPartial(partial)
                }
            }
            try Task.checkCancellation()
            let transcript = try await manager.finish()
            try Task.checkCancellation()
            try await manager.reset()
            return transcript
        } catch {
            try? await manager.reset()
            throw error
        }
    }

    func unloadModel() {
        voxtralRealtimeModel = nil
        qwen3AsrModel = nil
        parakeetAsrManager = nil
        whisperKitInstance = nil
        unifiedAsrManager = nil
        loadedModel = nil
    }

    private func normalizeQwenTranscript(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeParakeetTranscript(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum MLXError: LocalizedError {
    case invalidModelIdentifier(String)
    case pipelineUnavailable

    var errorDescription: String? {
        switch self {
        case let .invalidModelIdentifier(identifier):
            return "Invalid model identifier: \(identifier)"
        case .pipelineUnavailable:
            return "Transcription pipeline is not available."
        }
    }
}

private func normalizeDownloadError(_ error: any Error) -> MLXDownloadError {
    if let downloadError = error as? MLXDownloadError {
        return downloadError
    }

    if let downloaderError = error as? VoxtralCore.ModelDownloaderError {
        switch downloaderError {
        case .downloadPaused:
            return .paused
        case .downloadCancelled:
            return .cancelled
        case .aria2BinaryMissing:
            return .aria2BinaryMissing
        case let .downloadFailed(message):
            return .failed(message)
        case .modelNotFound:
            return .failed(downloaderError.localizedDescription)
        }
    }

    return .failed(error.localizedDescription)
}

private enum FluidAudioModel: Sendable, Equatable {
    case parakeetUnified
    case parakeetTdtCtc110m

    init?(info: MLXModelInfo) {
        let normalizedID = info.id.lowercased()
        let normalizedRepo = info.repoId.lowercased()

        switch normalizedID {
        case MLXPipelineModel.parakeetUnified06B.rawValue:
            self = .parakeetUnified
        case MLXPipelineModel.parakeetTDTCTC110M.rawValue:
            self = .parakeetTdtCtc110m
        default:
            switch normalizedRepo {
            case "fluidinference/parakeet-unified-en-0.6b-coreml":
                self = .parakeetUnified
            case "fluidinference/parakeet-tdt-ctc-110m-coreml":
                self = .parakeetTdtCtc110m
            default:
                return nil
            }
        }
    }

    var parakeetVersion: AsrModelVersion? {
        switch self {
        case .parakeetUnified: return nil
        case .parakeetTdtCtc110m: return .tdtCtc110m
        }
    }

    var parakeetRepoId: String? {
        switch self {
        case .parakeetUnified: return nil
        case .parakeetTdtCtc110m: return "FluidInference/parakeet-tdt-ctc-110m-coreml"
        }
    }

    var directoryURL: URL {
        switch self {
        case .parakeetUnified:
            return UnifiedModelArtifacts.directory
        case .parakeetTdtCtc110m:
            return AsrModels.defaultCacheDirectory(for: .tdtCtc110m)
        }
    }

    var candidateDirectoryURLs: [URL] {
        switch self {
        case .parakeetUnified, .parakeetTdtCtc110m:
            return [directoryURL]
        }
    }

    var displayName: String {
        switch self {
        case .parakeetUnified:
            return "Parakeet Unified"
        case .parakeetTdtCtc110m:
            return "Parakeet TDT-CTC 110M"
        }
    }
}

private enum FluidAudioCache {
    static func isModelDownloaded(info: MLXModelInfo) -> Bool {
        guard let model = FluidAudioModel(info: info) else { return false }
        return isModelDownloaded(model: model)
    }

    static func downloadIfNeeded(
        info: MLXModelInfo,
        progress: @escaping @Sendable (Double, String) -> Void
    ) async throws {
        guard let model = FluidAudioModel(info: info) else {
            throw MLXError.invalidModelIdentifier(info.id)
        }
        _ = try await downloadIfNeeded(model: model, progress: progress)
    }

    @discardableResult
    static func downloadIfNeeded(model: FluidAudioModel) async throws -> URL {
        try await downloadIfNeeded(model: model, progress: nil)
    }

    static func modelDirectoryURL(info: MLXModelInfo) -> URL? {
        guard let model = FluidAudioModel(info: info) else { return nil }
        return resolvedDirectoryURL(for: model)
    }

    static func deleteModel(info: MLXModelInfo) throws {
        guard let model = FluidAudioModel(info: info) else {
            throw MLXError.invalidModelIdentifier(info.id)
        }
        for directory in model.candidateDirectoryURLs {
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        }
    }

    /// AsrModels.modelsExist replaces the folder name with its own, so it cannot check a legacy folder.
    private static func parakeetFilesExist(at directory: URL, version: AsrModelVersion) -> Bool {
        let models: Set<String>
        switch version {
        case .tdtCtc110m: models = ModelNames.ASR.requiredModelsFused
        default: models = ModelNames.ASR.requiredModels
        }
        return models.union([ModelNames.ASR.vocabularyFile]).allSatisfy {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
    }

    private static func isModelDownloaded(model: FluidAudioModel) -> Bool {
        resolvedDirectoryURL(for: model) != nil
    }

    private static func resolvedDirectoryURL(for model: FluidAudioModel) -> URL? {
        switch model {
        case .parakeetUnified:
            return UnifiedModelArtifacts.isDownloaded(at: model.directoryURL) ? model.directoryURL : nil
        case .parakeetTdtCtc110m:
            guard let version = model.parakeetVersion else { return nil }
            return model.candidateDirectoryURLs.first { parakeetFilesExist(at: $0, version: version) }
        }
    }

    @discardableResult
    private static func downloadIfNeeded(
        model: FluidAudioModel,
        progress: (@Sendable (Double, String) -> Void)?
    ) async throws -> URL {
        if let existingDirectory = resolvedDirectoryURL(for: model) {
            progress?(1, "Model already downloaded")
            return existingDirectory
        }

        progress?(0, "Downloading \(model.displayName) model...")

        switch model {
        case .parakeetUnified:
            try await ModelDownloader.downloadFromHuggingFace(
                repoId: Repo.parakeetUnified.rawValue,
                subfolder: nil,
                destination: model.directoryURL,
                fileFilter: UnifiedModelArtifacts.includes,
                progress: progress
            )
            try UnifiedModelArtifacts.recordCompletedDownload(at: model.directoryURL)
        case .parakeetTdtCtc110m:
            guard let repoId = model.parakeetRepoId else {
                throw MLXError.invalidModelIdentifier(model.displayName)
            }
            try await ModelDownloader.downloadFromHuggingFace(
                repoId: repoId,
                subfolder: nil,
                destination: model.directoryURL,
                fileFilter: nil,
                progress: progress
            )
        }

        guard let resolvedDirectory = resolvedDirectoryURL(for: model) else {
            throw MLXDownloadError.failed("Downloaded model files were not detected in cache.")
        }

        progress?(1, "Download complete")
        return resolvedDirectory
    }
}

private extension MLXModelInfo {
    var voxtralModelInfo: VoxtralModelInfo {
        if let model = ModelRegistry.model(withId: id) {
            return model
        }

        return VoxtralModelInfo(
            id: id,
            repoId: repoId,
            name: name,
            description: summary,
            size: size ?? "",
            quantization: quantization,
            parameters: parameters,
            recommended: recommended
        )
    }
}

private extension MLXPipelineModel {
    var fluidAudioModel: FluidAudioModel? {
        switch self {
        case .parakeetUnified06B:
            return .parakeetUnified
        case .parakeetTDTCTC110M:
            return .parakeetTdtCtc110m
        case .mini3b8bit, .qwen3ASR17B8bit, .whisperLargeV3Turbo:
            return nil
        }
    }

    var whisperKitVariant: String? {
        switch self {
        case .whisperLargeV3Turbo:
            return "openai_whisper-large-v3_turbo_954MB"
        case .mini3b8bit, .parakeetUnified06B, .qwen3ASR17B8bit, .parakeetTDTCTC110M:
            return nil
        }
    }

}

private enum WhisperKitCache {
    static func isModelDownloaded(variant: String) -> Bool {
        guard let url = modelDirectoryURL(variant: variant) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func downloadIfNeeded(
        variant: String,
        progress: @escaping @Sendable (Double, String) -> Void
    ) async throws {
        if isModelDownloaded(variant: variant) {
            progress(1, "Model already downloaded")
            return
        }

        progress(0, "Downloading WhisperKit model...")
        let modelName = whisperKitModelName(for: variant)
        let modelDir = petalDirectory
            .appendingPathComponent("models")
            .appendingPathComponent("argmaxinc")
            .appendingPathComponent("whisperkit-coreml")
            .appendingPathComponent(modelName)

        try await ModelDownloader.downloadFromHuggingFace(
            repoId: "argmaxinc/whisperkit-coreml",
            subfolder: modelName,
            destination: modelDir,
            fileFilter: nil,
            progress: progress
        )
        progress(1, "Download complete")
    }

    static func deleteModel(variant: String) throws {
        guard let url = modelDirectoryURL(variant: variant) else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    static func modelDirectoryURL(variant: String) -> URL? {
        let baseDirectory = petalDirectory
            .appendingPathComponent("models")
            .appendingPathComponent("argmaxinc")
            .appendingPathComponent("whisperkit-coreml")

        let modelDirectory = baseDirectory.appendingPathComponent(whisperKitModelName(for: variant))
        guard FileManager.default.fileExists(atPath: modelDirectory.path) else { return nil }
        return modelDirectory
    }

    private static func whisperKitModelName(for variant: String) -> String {
        switch variant {
        case "whisper-large-v3-turbo":
            return "openai_whisper-large-v3_turbo_954MB"
        default:
            return variant
        }
    }
}

private extension MLXPipelineModel {
    var huggingFaceModelInfo: VoxtralModelInfo? {
        guard case .qwen3ASR17B8bit = self else { return voxtralRealtimeModelInfo }
        return VoxtralModelInfo(
            id: rawValue,
            repoId: "mlx-community/Qwen3-ASR-1.7B-8bit",
            name: "Qwen3 ASR 1.7B",
            description: "Multilingual transcription with automatic language detection.",
            size: "~2.5 GB",
            quantization: "8-bit MLX",
            parameters: "1.7B"
        )
    }

    var voxtralRealtimeModelInfo: VoxtralModelInfo? {
        guard case .mini3b8bit = self else { return nil }
        return VoxtralModelInfo(
            id: "voxtral-realtime-4b-2602-4bit",
            repoId: "mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit",
            name: "Voxtral Realtime 4B",
            description: "Mistral's streaming transcription model for 13 languages.",
            size: "~3.2 GB",
            quantization: "4-bit MLX",
            parameters: "4B"
        )
    }
}

private extension MLXTranscriptionMode {
    var logSummary: String {
        switch self {
        case .verbatim:
            return "verbatim"
        case let .smart(prompt):
            return "smart(promptChars=\(prompt.count))"
        }
    }
}

private func formatElapsedSeconds(_ seconds: Double) -> String {
    String(format: "%.3fs", seconds)
}

private func mlxAudioDurationSeconds(_ url: URL) -> Double {
    guard let file = try? AVAudioFile(forReading: url) else { return 0 }
    let sampleRate = file.fileFormat.sampleRate
    guard sampleRate > 0 else { return 0 }
    return Double(file.length) / sampleRate
}

private func mlxAudioFileSizeBytes(_ url: URL) -> Int64? {
    let values = try? url.resourceValues(forKeys: [.fileSizeKey])
    guard let size = values?.fileSize else { return nil }
    return Int64(size)
}
