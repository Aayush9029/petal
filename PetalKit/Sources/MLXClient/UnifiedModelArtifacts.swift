import FluidAudio
import Foundation

/// One latency tier keeps the model picker simple and avoids downloading unused encoders.
enum UnifiedModelArtifacts {
    static let config = UnifiedConfig(chunkFrames: 7, rightFrames: 1)
    static let requiredFiles = ModelNames.ParakeetUnified.requiredModels(variant: nil).union([
        ModelNames.ParakeetUnified.streamingEncoderFile(precision: .int8, contextSuffix: config.contextSuffix)
    ])
    private static let receiptName = ".petal-unified-640ms-int8.json"

    static var directory: URL {
        AsrModels.defaultCacheDirectory().deletingLastPathComponent()
            .appendingPathComponent(Repo.parakeetUnified.folderName, isDirectory: true)
    }

    static func includes(_ path: String) -> Bool {
        requiredFiles.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    /// A model directory can exist while aria2 is still downloading its weights.
    /// Record file sizes only after the downloader has verified every requested file.
    static func recordCompletedDownload(at directory: URL) throws {
        let files = try inventory(at: directory)
        try JSONEncoder().encode(files).write(to: directory.appendingPathComponent(receiptName), options: .atomic)
    }

    static func isDownloaded(at directory: URL) -> Bool {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(receiptName)),
              let receipt = try? JSONDecoder().decode([String: Int].self, from: data),
              let files = try? inventory(at: directory)
        else { return false }
        return receipt == files
    }

    private static func inventory(at directory: URL) throws -> [String: Int] {
        let manager = FileManager.default
        guard requiredFiles.allSatisfy({ manager.fileExists(atPath: directory.appendingPathComponent($0).path) }),
              let enumerator = manager.enumerator(atPath: directory.path)
        else { throw MLXDownloadError.failed("Parakeet Unified download is incomplete.") }

        var files: [String: Int] = [:]
        for case let path as String in enumerator {
            guard includes(path) else { continue }
            let url = directory.appendingPathComponent(path)
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { continue }
            guard let size = values.fileSize, size > 0, url.pathExtension != "aria2" else {
                throw MLXDownloadError.failed("Parakeet Unified download is incomplete.")
            }
            files[path] = size
        }
        guard requiredFiles.allSatisfy({ name in files.keys.contains { $0 == name || $0.hasPrefix(name + "/") } }) else {
            throw MLXDownloadError.failed("Parakeet Unified download is incomplete.")
        }
        return files
    }
}
