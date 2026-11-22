import DownloadClient
import Foundation
import Shared
import VoxtralCore

enum LocalCleanupModelFiles {
    static let info = VoxtralModelInfo(
        id: CleanupModel.petalW1.rawValue, repoId: "Aayush9029/petal-w1-4bit", name: CleanupModel.petalW1.displayName,
        description: "Transcript cleanup model fine-tuned from Qwen3.5-2B", size: "1.0 GB", quantization: "MLX 4-bit", parameters: "2B"
    )
    private static let revision = "v1.4"
    private static let revisionFile = ".petal-revision"

    static var directory: URL? {
        if let cached = ModelDownloader.findModelPath(for: info), isComplete(at: cached) { return cached }
        let local = ModelDownloader.localPath(for: info)
        return isComplete(at: local) ? local : nil
    }

    private static var legacyDirectory: URL? {
        ModelDownloader.findModelPath(for: .init(
            id: "petal-w1", repoId: "Aayush9029/petal-w1", name: "Petal W1", description: "",
            size: "782 MB", quantization: "MLX 8-bit", parameters: "0.8B"
        ))
    }

    static var retiredDirectory: URL? {
        ModelDownloader.findModelPath(for: .init(
            id: "s1-mini-mlx-8bit", repoId: "Aayush9029/s1-mini-mlx-8bit", name: "S1-mini", description: "",
            size: "619 MB", quantization: "MLX 8-bit", parameters: "0.6B"
        ))
    }

    static var isOutdated: Bool {
        guard let directory else { return legacyDirectory != nil }
        return !isCurrent(at: directory)
    }

    static func install(progress: @escaping DownloadProgressCallback) async throws {
        if let directory, !isCurrent(at: directory) {
            let manager = FileManager.default
            let staging = try manager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: directory, create: true)
            defer { try? manager.removeItem(at: staging) }
            let replacement = staging.appending(path: "weights")
            try await download(to: replacement, progress: progress)
            _ = try manager.replaceItemAt(directory, withItemAt: replacement)
        } else if directory == nil {
            try await download(to: ModelDownloader.localPath(for: info), progress: progress)
        }
        if let legacyDirectory { try? FileManager.default.removeItem(at: legacyDirectory) }
    }

    static func delete() throws {
        if let directory { try FileManager.default.removeItem(at: directory) }
        if let legacyDirectory { try FileManager.default.removeItem(at: legacyDirectory) }
    }

    private static func isCurrent(at directory: URL) -> Bool {
        let recorded = try? String(contentsOf: directory.appending(path: revisionFile), encoding: .utf8)
        return recorded?.trimmingCharacters(in: .whitespacesAndNewlines) == revision
    }

    private static func isComplete(at directory: URL) -> Bool {
        ModelWeights.hasContents(directory.appending(path: "tokenizer.json"))
            && ModelWeights.hasContents(directory.appending(path: "tokenizer_config.json"))
            && ModelWeights.areComplete(at: directory)
    }

    private static func download(to directory: URL, progress: @escaping DownloadProgressCallback) async throws {
        try await ModelDownloader.downloadFromHuggingFace(
            repoId: info.repoId, subfolder: nil, destination: directory,
            fileFilter: { ["json", "safetensors", "txt"].contains(($0 as NSString).pathExtension) },
            progress: progress
        )
        guard isComplete(at: directory) else { throw LocalCleanupError.incompleteDownload }
        try revision.write(to: directory.appending(path: revisionFile), atomically: true, encoding: .utf8)
    }
}
