import CryptoKit
import FluidAudio
import Foundation
import Shared
import VoxtralCore

package struct QwenModelSpec: Sendable {
    package struct RootConfigReceipt: Sendable, Equatable {
        package let localFileName: String
        package let expectedByteCount: Int
        package let expectedSHA256: String

        package init(localFileName: String, expectedByteCount: Int, expectedSHA256: String) {
            self.localFileName = localFileName
            self.expectedByteCount = expectedByteCount
            self.expectedSHA256 = expectedSHA256
        }
    }

    package let info: VoxtralModelInfo
    package let revision: String
    package let subfolder: String?
    package let rootConfigReceipt: RootConfigReceipt?
    package let allowedExtensions: Set<String>

    package init(
        info: VoxtralModelInfo,
        revision: String = "main",
        subfolder: String? = nil,
        rootConfigReceipt: RootConfigReceipt? = nil,
        allowedExtensions: Set<String> = ["json", "safetensors", "txt"]
    ) {
        self.info = info
        self.revision = revision
        self.subfolder = subfolder
        self.rootConfigReceipt = rootConfigReceipt
        self.allowedExtensions = allowedExtensions
    }
}

package enum SpeechModelFiles: Sendable {
    case qwen(QwenModelSpec)
    case voxtral(VoxtralModelInfo)
    case unified(UnifiedModelArtifacts)
    case parakeet(AsrModelVersion)
    case whisperKit

    package static let fourierRevision = "1c5ad7635cbdc698778eab92ae7a202c60329097"
    package static let fourierSubfolder = "mlx/8bit"
    package static let fourierRootConfigFileName = ".hf-root-config.json"
    package static let fourierRootConfigByteCount = 2479
    package static let fourierRootConfigSHA256 = "5bc1d99c141fc866b61efca97dcbc6412a38db25ff0934c38bf7b46fa09485a2"

    package init?(_ model: ModelOption) {
        switch model {
        case .appleSpeech:
            return nil
        case .qwen3ASR17B8bit:
            self = .qwen(QwenModelSpec(info: VoxtralModelInfo(model)))
        case .orukFourier2B8bit:
            self = .qwen(QwenModelSpec(
                info: VoxtralModelInfo(model),
                revision: Self.fourierRevision,
                subfolder: Self.fourierSubfolder,
                rootConfigReceipt: .init(
                    localFileName: Self.fourierRootConfigFileName,
                    expectedByteCount: Self.fourierRootConfigByteCount,
                    expectedSHA256: Self.fourierRootConfigSHA256
                ),
                allowedExtensions: ["json", "safetensors", "txt", "jinja"]
            ))
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
        case let .qwen(spec): ModelDownloader.localPath(for: spec.info)
        case let .voxtral(info): ModelDownloader.localPath(for: info)
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
        case let .qwen(spec) where spec.subfolder == nil:
            if let cached = ModelDownloader.findModelPath(for: spec.info), isComplete(at: cached) { return cached }
        case let .voxtral(info):
            if let cached = ModelDownloader.findModelPath(for: info), isComplete(at: cached) { return cached }
        default:
            break
        }
        return isComplete(at: directory) ? directory : nil
    }

    private static func hasQwenModelFiles(at directory: URL) -> Bool {
        let hasTokenizer = ModelWeights.hasContents(directory.appending(path: "tokenizer.json"))
            || ["vocab.json", "merges.txt"].allSatisfy { ModelWeights.hasContents(directory.appending(path: $0)) }
        return hasTokenizer && ModelWeights.hasContents(directory.appending(path: "tokenizer_config.json"))
            && ModelWeights.areComplete(at: directory)
    }

    func isComplete(at directory: URL) -> Bool {
        switch self {
        case let .qwen(spec):
            let hasRootConfig = spec.rootConfigReceipt.map {
                ModelWeights.hasContents(directory.appending(path: $0.localFileName))
            } ?? true
            return Self.hasQwenModelFiles(at: directory) && hasRootConfig
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

        let revision: String
        let subfolder: String?
        let filter: ((String) -> Bool)?
        switch self {
        case let .unified(artifacts):
            progress(0, "Downloading \(artifacts.displayName) model...")
            revision = "main"
            subfolder = artifacts.subfolder
            filter = artifacts.includes
        case let .parakeet(version):
            let isV3 = version == .v3
            progress(0, isV3 ? "Downloading Parakeet TDT 0.6B V3 model..." : "Downloading Parakeet TDT-CTC 110M model...")
            revision = "main"
            subfolder = nil
            // The v3 repository also ships several GB of unused encoder variants.
            let files = Self.parakeetFiles(version)
            filter = isV3 ? { path in files.contains { path == $0 || path.hasPrefix($0 + "/") } } : nil
        case .whisperKit:
            progress(0, "Downloading WhisperKit model...")
            revision = "main"
            subfolder = Self.whisperVariant
            filter = nil
        case let .qwen(spec):
            revision = spec.revision
            subfolder = spec.subfolder
            let extensions = spec.allowedExtensions
            filter = { extensions.contains(($0 as NSString).pathExtension) }
        case .voxtral:
            revision = "main"
            subfolder = nil
            filter = { ["json", "safetensors", "txt"].contains(($0 as NSString).pathExtension) }
        }

        if case .whisperKit = self {
            if !Self.hasWhisperWeights(at: directory) {
                try await ModelDownloader.downloadFromHuggingFace(
                    repoId: repoID, revision: revision, subfolder: subfolder, destination: directory, fileFilter: nil, progress: progress
                )
            }
            if Self.whisperTokenizerDirectory(in: directory) == nil {
                try await ModelDownloader.downloadFromHuggingFace(
                    repoId: Self.whisperTokenizer, subfolder: nil,
                    destination: ModelDownloader.modelsDirectory.appending(path: Self.whisperTokenizer),
                    fileFilter: Self.tokenizerFiles.contains, progress: progress
                )
            }
        } else if case let .qwen(spec) = self, let receipt = spec.rootConfigReceipt {
            if !Self.hasQwenModelFiles(at: directory) {
                try await ModelDownloader.downloadFromHuggingFace(
                    repoId: repoID, revision: revision, subfolder: subfolder, destination: directory, fileFilter: filter, progress: progress
                )
            }
            // Fetch repo-root config.json last so aborted weight transfers do not register Hub downloads,
            // and save it beside mlx/8bit/config.json without overwriting the quantized MLX config.
            try Task.checkCancellation()
            if !ModelWeights.hasContents(directory.appending(path: receipt.localFileName)) {
                try await Self.downloadRootConfig(repoID: repoID, revision: revision, to: directory, receipt: receipt)
            }
        } else {
            try await ModelDownloader.downloadFromHuggingFace(
                repoId: repoID, revision: revision, subfolder: subfolder, destination: directory, fileFilter: filter, progress: progress
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

    package static func rootConfigURL(repoID: String, revision: String) -> URL? {
        URL(string: "https://huggingface.co/\(repoID)/resolve/\(revision)/config.json?download=true")
    }

    package static func downloadRootConfig(
        repoID: String,
        revision: String,
        to directory: URL,
        receipt: QwenModelSpec.RootConfigReceipt,
        fetch: @Sendable (URL) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(from: $0) }
    ) async throws {
        guard let url = rootConfigURL(repoID: repoID, revision: revision) else {
            throw DownloadClientFailure.failed("Invalid HuggingFace config URL for \(repoID).")
        }
        let (data, response) = try await fetch(url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw DownloadClientFailure.failed("Failed to fetch repository config.json for \(repoID).")
        }
        try writeRootConfig(data, to: directory, receipt: receipt)
    }

    package static func writeRootConfig(
        _ data: Data,
        to directory: URL,
        receipt: QwenModelSpec.RootConfigReceipt
    ) throws {
        guard data.count == receipt.expectedByteCount else {
            throw DownloadClientFailure.failed("Unexpected repository config.json size (\(data.count) bytes).")
        }
        let digest = SHA256.hash(data: data)
            .map { byte in (byte < 16 ? "0" : "") + String(byte, radix: 16) }
            .joined()
        guard digest == receipt.expectedSHA256 else {
            throw DownloadClientFailure.failed("Repository config.json checksum mismatch.")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appending(path: receipt.localFileName), options: .atomic)
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
