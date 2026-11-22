import FluidAudio
import Foundation
import Shared
import VoxtralCore

package enum SpeechModelFiles: Sendable {
    case qwen(VoxtralModelInfo)
    case voxtral(VoxtralModelInfo)
    case unified(UnifiedModelArtifacts)
    case parakeet(AsrModelVersion)
    case whisperKit

    package init?(_ model: ModelOption) {
        switch model {
        case .appleSpeech:
            return nil
        case .qwen3ASR17B8bit: self = .qwen(VoxtralModelInfo(model))
        case .mini3b8bit: self = .voxtral(VoxtralModelInfo(model))
        case .parakeetUnified06B: self = .unified(.parakeet)
        case .nemotronUnified06B: self = .unified(.nemotron)
        case .parakeetTDT06BV3: self = .parakeet(.v3)
        case .parakeetTDTCTC110M: self = .parakeet(.tdtCtc110m)
        case .whisperLargeV3Turbo: self = .whisperKit
        }
    }

    private static let whisperVariant = "openai_whisper-large-v3_turbo_954MB"

    var directory: URL {
        switch self {
        case let .qwen(info), let .voxtral(info): ModelDownloader.localPath(for: info)
        case let .unified(artifacts): artifacts.directory
        case let .parakeet(version): AsrModels.defaultCacheDirectory(for: version)
        case .whisperKit:
            ModelDownloader.modelsDirectory
                .appending(path: ModelOption.whisperLargeV3Turbo.descriptor.repoID)
                .appending(component: Self.whisperVariant)
        }
    }

    var installedDirectory: URL? {
        switch self {
        case let .qwen(info), let .voxtral(info):
            if let cached = ModelDownloader.findModelPath(for: info), isComplete(at: cached) { return cached }
        default:
            break
        }
        return isComplete(at: directory) ? directory : nil
    }

    func isComplete(at directory: URL) -> Bool {
        switch self {
        case .qwen:
            let hasTokenizer = ModelWeights.hasContents(directory.appending(path: "tokenizer.json"))
                || ["vocab.json", "merges.txt"].allSatisfy { ModelWeights.hasContents(directory.appending(path: $0)) }
            return hasTokenizer && ModelWeights.hasContents(directory.appending(path: "tokenizer_config.json"))
                && ModelWeights.areComplete(at: directory)
        case .voxtral:
            return ModelWeights.hasContents(directory.appending(path: "tekken.json")) && ModelWeights.areComplete(at: directory)
        case let .unified(artifacts):
            return artifacts.isDownloaded(at: directory)
        case let .parakeet(version):
            let files = Self.parakeetFiles(version)
            return files.allSatisfy { FileManager.default.fileExists(atPath: directory.appending(path: $0).path) }
                && !ModelWeights.hasIncompleteTransfer(at: directory)
        case .whisperKit:
            return Self.hasWhisperWeights(at: directory) && Self.whisperTokenizerDirectory(in: directory) != nil
        }
    }

    private static let whisperTokenizer = "openai/whisper-large-v3"
    private static let tokenizerFiles: Set<String> = ["tokenizer.json", "tokenizer_config.json"]

    package static func whisperTokenizerDirectory(in modelDirectory: URL) -> URL? {
        let models = ModelDownloader.modelsDirectory
        let folders = [
            models.appending(path: whisperTokenizer), models.deletingLastPathComponent(),
            modelDirectory, modelDirectory.appending(path: "models").appending(path: whisperTokenizer),
        ]
        return folders.first { folder in
            tokenizerFiles.allSatisfy { file in
                ModelWeights.hasContents(folder.appending(path: file)) &&
                    !FileManager.default.fileExists(atPath: folder.appending(path: file + ".aria2").path)
            }
        }
    }

    private static func hasWhisperWeights(at directory: URL) -> Bool {
        let manager = FileManager.default
        let models = ["MelSpectrogram", "AudioEncoder", "TextDecoder"]
        return models.allSatisfy { name in
            ["mlmodelc", "mlpackage/Data/com.apple.CoreML/model.mlmodel"].contains { suffix in
                manager.fileExists(atPath: directory.appending(path: "\(name).\(suffix)").path)
            }
        } && !ModelWeights.hasIncompleteTransfer(at: directory)
    }

    func download(repoID: String, progress: @escaping DownloadProgressCallback) async throws {
        if installedDirectory != nil {
            progress(1, "Model already downloaded")
            return
        }

        let subfolder: String?
        let filter: ((String) -> Bool)?
        switch self {
        case let .unified(artifacts):
            progress(0, "Downloading \(artifacts.displayName) model...")
            subfolder = artifacts.subfolder
            filter = artifacts.includes
        case let .parakeet(version):
            let isV3 = version == .v3
            progress(0, isV3 ? "Downloading Parakeet TDT 0.6B V3 model..." : "Downloading Parakeet TDT-CTC 110M model...")
            subfolder = nil
            // The v3 repository also ships several GB of unused encoder variants.
            let files = Self.parakeetFiles(version)
            filter = isV3 ? { path in files.contains { path == $0 || path.hasPrefix($0 + "/") } } : nil
        case .whisperKit:
            progress(0, "Downloading WhisperKit model...")
            subfolder = Self.whisperVariant
            filter = nil
        case .qwen, .voxtral:
            subfolder = nil
            filter = { ["json", "safetensors", "txt"].contains(($0 as NSString).pathExtension) }
        }

        if case .whisperKit = self {
            if !Self.hasWhisperWeights(at: directory) {
                try await ModelDownloader.downloadFromHuggingFace(
                    repoId: repoID, subfolder: subfolder, destination: directory, fileFilter: nil, progress: progress
                )
            }
            if Self.whisperTokenizerDirectory(in: directory) == nil {
                try await ModelDownloader.downloadFromHuggingFace(
                    repoId: Self.whisperTokenizer, subfolder: nil,
                    destination: ModelDownloader.modelsDirectory.appending(path: Self.whisperTokenizer),
                    fileFilter: Self.tokenizerFiles.contains, progress: progress
                )
            }
        } else {
            try await ModelDownloader.downloadFromHuggingFace(
                repoId: repoID, subfolder: subfolder, destination: directory, fileFilter: filter, progress: progress
            )
        }
        if case let .unified(artifacts) = self {
            try artifacts.recordCompletedDownload(at: directory)
        }
        guard installedDirectory != nil else {
            throw DownloadClientFailure.failed("Downloaded model files were not detected in cache.")
        }
        progress(1, "Download complete")
    }

    private static func parakeetFiles(_ version: AsrModelVersion) -> Set<String> {
        let bundles = version == .v3 ? ModelNames.ASR.requiredModelsV3() : ModelNames.ASR.requiredModelsFused
        return bundles.union([ModelNames.ASR.vocabularyFile])
    }
}

private extension VoxtralModelInfo {
    init(_ model: ModelOption) {
        let descriptor = model.descriptor
        self.init(
            id: model.rawValue, repoId: descriptor.repoID, name: descriptor.name,
            description: descriptor.summary, size: descriptor.size ?? "",
            quantization: descriptor.quantization, parameters: descriptor.parameters,
            recommended: descriptor.recommended
        )
    }
}
