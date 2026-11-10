import FluidAudio
import Foundation

/// One latency tier for each model keeps the model picker simple and avoids downloading unused encoders.
struct UnifiedModelArtifacts: Sendable {
    let config: UnifiedConfig
    let precision: UnifiedEncoderPrecision
    let displayName: String
    /// The Hugging Face folder that holds the model bundles, when they are not at the repository root.
    let subfolder: String?
    private let receiptName: String

    static let parakeet = UnifiedModelArtifacts(
        config: UnifiedConfig(chunkFrames: 7, rightFrames: 1),
        precision: .int8,
        displayName: "Parakeet Unified",
        subfolder: nil,
        receiptName: ".petal-unified-640ms-int8.json"
    )

    /// The int8 Nemotron encoder loses accuracy in French, so this model uses fp16.
    static let nemotron = UnifiedModelArtifacts(
        config: UnifiedConfig(chunkFrames: 7, rightFrames: 7, family: .nemotronMultilingual(.auto)),
        precision: .fp16,
        displayName: "Nemotron Unified",
        subfolder: "coreml",
        receiptName: ".petal-nemotron-unified-1120ms-fp16.json"
    )

    var repoID: String {
        let path = config.family.repo.rawValue
        guard let subfolder, path.hasSuffix("/" + subfolder) else { return path }
        return String(path.dropLast(subfolder.count + 1))
    }

    var requiredFiles: Set<String> {
        let family = config.family
        return [
            family.streamingEncoderFile(precision: precision, contextSuffix: config.contextSuffix),
            family.decoderFile,
            family.jointDecisionFile,
            family.vocab,
            family.metadata,
        ]
    }

    var directory: URL {
        AsrModels.defaultCacheDirectory().deletingLastPathComponent()
            .appendingPathComponent(config.family.repo.folderName, isDirectory: true)
    }

    func makeManager() -> StreamingUnifiedAsrManager {
        StreamingUnifiedAsrManager(config: config, encoderPrecision: precision)
    }

    func includes(_ path: String) -> Bool {
        requiredFiles.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    /// A model directory can exist while aria2 is still downloading its weights.
    /// Record file sizes only after the downloader has verified every requested file.
    func recordCompletedDownload(at directory: URL) throws {
        let files = try inventory(at: directory)
        try JSONEncoder().encode(files).write(to: directory.appendingPathComponent(receiptName), options: .atomic)
    }

    func isDownloaded(at directory: URL) -> Bool {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(receiptName)),
              let receipt = try? JSONDecoder().decode([String: Int].self, from: data),
              let files = try? inventory(at: directory)
        else { return false }
        return receipt == files
    }

    private func inventory(at directory: URL) throws -> [String: Int] {
        let manager = FileManager.default
        guard requiredFiles.allSatisfy({ manager.fileExists(atPath: directory.appendingPathComponent($0).path) }),
              let enumerator = manager.enumerator(atPath: directory.path)
        else { throw MLXDownloadError.failed("\(displayName) download is incomplete.") }

        var files: [String: Int] = [:]
        for case let path as String in enumerator {
            guard includes(path) else { continue }
            let url = directory.appendingPathComponent(path)
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { continue }
            guard let size = values.fileSize, size > 0, url.pathExtension != "aria2" else {
                throw MLXDownloadError.failed("\(displayName) download is incomplete.")
            }
            files[path] = size
        }
        guard requiredFiles.allSatisfy({ name in files.keys.contains { $0 == name || $0.hasPrefix(name + "/") } }) else {
            throw MLXDownloadError.failed("\(displayName) download is incomplete.")
        }
        return files
    }
}
