import AVFoundation
import Dependencies
import DependenciesMacros
import FluidAudio
import Foundation
import LogClient
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
    case mini3b
    case mini3b8bit
    case qwen3ASR06B4bit
    case parakeetTDT06BV3
    case whisperLargeV3Turbo
    case whisperTiny
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
    private var voxtralPipeline: VoxtralPipeline?
    private var qwen3AsrManager: Qwen3AsrManager?
    private var parakeetAsrManager: AsrManager?
    private var whisperKitInstance: WhisperKit?

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
        case .mini3b, .mini3b8bit:
            log("prepare.voxtral.begin model=\(model.rawValue)")
            var config = VoxtralPipeline.Configuration.default
            config.maxTokens = 1024
            config.temperature = 0.0
            config.topP = 0.95
            config.repetitionPenalty = 1.15

            let pipeline = VoxtralPipeline(
                model: model.voxtralModel,
                backend: .hybrid,
                configuration: config
            )

            let loadStart = ProcessInfo.processInfo.systemUptime
            try await pipeline.loadModel()
            let loadElapsed = ProcessInfo.processInfo.systemUptime - loadStart
            log("prepare.voxtral.loaded elapsed=\(formatElapsedSeconds(loadElapsed))")
            voxtralPipeline = pipeline

        case .qwen3ASR06B4bit:
            guard let fluidAudioModel = model.fluidAudioModel else {
                throw MLXError.invalidModelIdentifier(model.rawValue)
            }
            log("prepare.qwen.begin")
            let resolveStart = ProcessInfo.processInfo.systemUptime
            let modelDirectory = try await FluidAudioCache.downloadIfNeeded(model: fluidAudioModel)
            let resolveElapsed = ProcessInfo.processInfo.systemUptime - resolveStart
            log(
                "prepare.qwen.model-ready elapsed=\(formatElapsedSeconds(resolveElapsed)), directory=\(modelDirectory.lastPathComponent)"
            )
            let manager = Qwen3AsrManager()
            let loadStart = ProcessInfo.processInfo.systemUptime
            try await manager.loadModels(from: modelDirectory)
            let loadElapsed = ProcessInfo.processInfo.systemUptime - loadStart
            log("prepare.qwen.loaded elapsed=\(formatElapsedSeconds(loadElapsed))")
            qwen3AsrManager = manager

        case .parakeetTDT06BV3:
            guard let fluidAudioModel = model.fluidAudioModel else {
                throw MLXError.invalidModelIdentifier(model.rawValue)
            }
            log("prepare.parakeet.begin")
            let resolveStart = ProcessInfo.processInfo.systemUptime
            let modelDirectory = try await FluidAudioCache.downloadIfNeeded(model: fluidAudioModel)
            let resolveElapsed = ProcessInfo.processInfo.systemUptime - resolveStart
            log(
                "prepare.parakeet.model-ready elapsed=\(formatElapsedSeconds(resolveElapsed)), directory=\(modelDirectory.lastPathComponent)"
            )
            let asrLoadStart = ProcessInfo.processInfo.systemUptime
            let asrModels = try await AsrModels.load(from: modelDirectory, version: .v3)
            let asrLoadElapsed = ProcessInfo.processInfo.systemUptime - asrLoadStart
            log("prepare.parakeet.asrModels-loaded elapsed=\(formatElapsedSeconds(asrLoadElapsed))")
            let manager = AsrManager(config: .default)
            let managerInitStart = ProcessInfo.processInfo.systemUptime
            try await manager.initialize(models: asrModels)
            let managerInitElapsed = ProcessInfo.processInfo.systemUptime - managerInitStart
            log("prepare.parakeet.manager-initialized elapsed=\(formatElapsedSeconds(managerInitElapsed))")
            parakeetAsrManager = manager

        case .whisperLargeV3Turbo, .whisperTiny:
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
            case .mini3b, .mini3b8bit:
                guard let voxtralPipeline else {
                    throw MLXError.pipelineUnavailable
                }

                let backendStart = ProcessInfo.processInfo.systemUptime
                switch mode {
                case .verbatim:
                    transcript = try await voxtralPipeline.transcribe(audio: audioURL, language: "en")
                case let .smart(prompt):
                    log("transcribe.voxtral.smart-prompt length=\(prompt.count)")
                    transcript = try await voxtralPipeline.chat(audio: audioURL, prompt: prompt, language: "en")
                }
                let backendElapsed = ProcessInfo.processInfo.systemUptime - backendStart
                log("transcribe.voxtral.backend completed elapsed=\(formatElapsedSeconds(backendElapsed))")

            case .qwen3ASR06B4bit:
                guard let qwen3AsrManager else {
                    throw MLXError.pipelineUnavailable
                }

                let resampleStart = ProcessInfo.processInfo.systemUptime
                let audioSamples = try audioConverter.resampleAudioFile(audioURL)
                let resampleElapsed = ProcessInfo.processInfo.systemUptime - resampleStart
                log(
                    "transcribe.qwen.resample completed elapsed=\(formatElapsedSeconds(resampleElapsed)), samples=\(audioSamples.count)"
                )

                let inferenceStart = ProcessInfo.processInfo.systemUptime
                let text = try await qwen3AsrManager.transcribe(audioSamples: audioSamples)
                let inferenceElapsed = ProcessInfo.processInfo.systemUptime - inferenceStart
                log(
                    "transcribe.qwen.inference completed elapsed=\(formatElapsedSeconds(inferenceElapsed)), rawChars=\(text.count)"
                )

                let normalizedText = normalizeQwenTranscript(text)
                guard !normalizedText.isEmpty else {
                    log("transcribe.qwen.empty-normalized-output")
                    throw MLXError.pipelineUnavailable
                }
                log("transcribe.qwen.normalized chars=\(normalizedText.count)")
                transcript = normalizedText

            case .parakeetTDT06BV3:
                guard let parakeetAsrManager else {
                    throw MLXError.pipelineUnavailable
                }

                nonisolated(unsafe) let manager = parakeetAsrManager
                let inferenceStart = ProcessInfo.processInfo.systemUptime
                let result = try await manager.transcribe(audioURL, source: .system)
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

            case .whisperLargeV3Turbo, .whisperTiny:
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

    func unloadModel() {
        voxtralPipeline?.unload()
        voxtralPipeline = nil
        qwen3AsrManager = nil
        parakeetAsrManager = nil
        whisperKitInstance = nil
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

    if let downloaderError = error as? ModelDownloaderError {
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
    case qwen3Asr
    case parakeetTdt06BV3

    init?(info: MLXModelInfo) {
        let normalizedID = info.id.lowercased()
        let normalizedRepo = info.repoId.lowercased()

        switch normalizedID {
        case MLXPipelineModel.qwen3ASR06B4bit.rawValue:
            self = .qwen3Asr
        case MLXPipelineModel.parakeetTDT06BV3.rawValue:
            self = .parakeetTdt06BV3
        default:
            switch normalizedRepo {
            case "fluidinference/qwen3-asr-0.6b-coreml/f32",
                 "fluidinference/qwen3-asr-0.6b-coreml/int8",
                 "mlx-community/qwen3-asr-0.6b-4bit":
                self = .qwen3Asr
            case "fluidinference/parakeet-tdt-0.6b-v3-coreml",
                 "mlx-community/parakeet-tdt-0.6b-v3":
                self = .parakeetTdt06BV3
            default:
                return nil
            }
        }
    }

    var directoryURL: URL {
        switch self {
        case .qwen3Asr:
            return Qwen3AsrModels.defaultCacheDirectory()
        case .parakeetTdt06BV3:
            return AsrModels.defaultCacheDirectory(for: .v3)
        }
    }

    var candidateDirectoryURLs: [URL] {
        switch self {
        case .qwen3Asr:
            let defaultDirectory = Qwen3AsrModels.defaultCacheDirectory()
            let repoDirectory = defaultDirectory.deletingLastPathComponent()
            let modelsRoot = repoDirectory.deletingLastPathComponent()

            return [
                defaultDirectory,
                repoDirectory,
                repoDirectory.appendingPathComponent("qwen3-asr-0.6b-coreml-f32", isDirectory: true),
                modelsRoot.appendingPathComponent("qwen3-asr-0.6b-coreml-f32", isDirectory: true),
            ]
        case .parakeetTdt06BV3:
            return [AsrModels.defaultCacheDirectory(for: .v3)]
        }
    }

    var displayName: String {
        switch self {
        case .qwen3Asr:
            return "Qwen3 ASR"
        case .parakeetTdt06BV3:
            return "Parakeet TDT"
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

    private static func isModelDownloaded(model: FluidAudioModel) -> Bool {
        resolvedDirectoryURL(for: model) != nil
    }

    private static func resolvedDirectoryURL(for model: FluidAudioModel) -> URL? {
        switch model {
        case .qwen3Asr:
            for candidate in model.candidateDirectoryURLs {
                if Qwen3AsrModels.modelsExist(at: candidate) {
                    return candidate
                }
            }
            return nil
        case .parakeetTdt06BV3:
            let defaultDirectory = model.directoryURL
            return AsrModels.modelsExist(at: defaultDirectory, version: .v3) ? defaultDirectory : nil
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
        case .qwen3Asr:
            try await ModelDownloader.downloadFromHuggingFace(
                repoId: "FluidInference/qwen3-asr-0.6b-coreml",
                subfolder: "f32",
                destination: Qwen3AsrModels.defaultCacheDirectory(),
                fileFilter: nil,
                progress: progress
            )
        case .parakeetTdt06BV3:
            try await ModelDownloader.downloadFromHuggingFace(
                repoId: "FluidInference/parakeet-tdt-0.6b-v3-coreml",
                subfolder: nil,
                destination: AsrModels.defaultCacheDirectory(for: .v3),
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
        case .qwen3ASR06B4bit:
            return .qwen3Asr
        case .parakeetTDT06BV3:
            return .parakeetTdt06BV3
        case .mini3b, .mini3b8bit, .whisperLargeV3Turbo, .whisperTiny:
            return nil
        }
    }

    var whisperKitVariant: String? {
        switch self {
        case .whisperLargeV3Turbo:
            return "openai_whisper-large-v3_turbo"
        case .whisperTiny:
            return "openai_whisper-tiny"
        case .mini3b, .mini3b8bit, .qwen3ASR06B4bit, .parakeetTDT06BV3:
            return nil
        }
    }

    var voxtralModel: VoxtralPipeline.Model {
        switch self {
        case .mini3b:
            return .mini3b
        case .mini3b8bit:
            return .mini3b8bit
        case .qwen3ASR06B4bit, .parakeetTDT06BV3, .whisperLargeV3Turbo, .whisperTiny:
            return .mini3b
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
        let baseDir = petalDirectory
            .appendingPathComponent("models")
            .appendingPathComponent("argmaxinc")
            .appendingPathComponent("whisperkit-coreml")

        let modelName = whisperKitModelName(for: variant)
        let modelDir = baseDir.appendingPathComponent(modelName)
        guard FileManager.default.fileExists(atPath: modelDir.path) else { return nil }
        return modelDir
    }

    private static func whisperKitModelName(for variant: String) -> String {
        switch variant {
        case "whisper-large-v3-turbo":
            return "openai_whisper-large-v3_turbo"
        case "whisper-tiny":
            return "openai_whisper-tiny"
        default:
            return variant
        }
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
