/**
 * ModelDownloader - Downloads Voxtral models from HuggingFace Hub
 *
 * Uses the Hub module from swift-transformers for downloads.
 * Provides progress tracking and local caching.
 */

import Foundation

/// Progress callback for download updates
/// Swift 6: @Sendable for safe cross-isolation usage
public typealias DownloadProgressCallback = @Sendable (Double, String) -> Void

/// Model downloader with HuggingFace Hub integration
public class ModelDownloader {

    // MARK: - Pause / Resume / Cancel

    private enum DownloadIntent { case active, paused, cancelled }

    nonisolated(unsafe) private static var daemonProcess: Process?
    nonisolated(unsafe) private static var rpcClient: Aria2RPCClient?
    nonisolated(unsafe) private static var activeGIDs: [String] = []
    nonisolated(unsafe) private static var downloadIntent: DownloadIntent = .active

    public static func pauseDownload() {
        guard downloadIntent == .active else { return }
        downloadIntent = .paused
        let client = rpcClient
        let gids = activeGIDs
        Task {
            for gid in gids {
                _ = try? await client?.pause(gid: gid)
            }
        }
    }

    public static func cancelDownload(modelPath: URL? = nil) {
        downloadIntent = .cancelled
        let client = rpcClient
        let gids = activeGIDs
        Task {
            for gid in gids {
                _ = try? await client?.forceRemove(gid: gid)
            }
            _ = try? await client?.forceShutdown()
        }
        if let p = daemonProcess, p.isRunning { p.terminate() }
        if let modelPath { try? FileManager.default.removeItem(at: modelPath) }
    }

    /// Default models directory (in Documents/petal/models)
    public static var modelsDirectory: URL {
        appDirectory.appendingPathComponent("models")
    }

    /// Check if a model is already downloaded
    public static func isModelDownloaded(_ model: VoxtralModelInfo, in directory: URL? = nil) -> Bool {
        let modelPath = localPath(for: model, in: directory)
        let configPath = modelPath.appendingPathComponent("config.json")
        return FileManager.default.fileExists(atPath: configPath.path)
    }

    /// Get local path for a model
    public static func localPath(for model: VoxtralModelInfo, in directory: URL? = nil) -> URL {
        let baseDir = directory ?? modelsDirectory
        // Use repo ID as folder name, replacing "/" with "--"
        let folderName = model.repoId.replacingOccurrences(of: "/", with: "--")
        return baseDir.appendingPathComponent(folderName)
    }

    /// List all downloaded models
    public static func listDownloadedModels(in directory: URL? = nil) -> [VoxtralModelInfo] {
        return ModelRegistry.models.filter { model in
            findModelPath(for: model) != nil
        }
    }

    /// Get the HuggingFace Hub cache path for a model
    /// Checks both the new Library/Caches location and the legacy ~/.cache/huggingface location
    public static func hubCachePath(for model: VoxtralModelInfo) -> URL? {
        // First check the new location: ~/Library/Caches/models/{org}/{repo}
        if let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let newPath = cacheDir
                .appendingPathComponent("models")
                .appendingPathComponent(model.repoId)

            if FileManager.default.fileExists(atPath: newPath.appendingPathComponent("config.json").path) {
                return newPath
            }
        }

        // Then check the legacy location: ~/.cache/huggingface/hub/models--{org}--{repo}/snapshots/...
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let hubCache = homeDir
            .appendingPathComponent(".cache")
            .appendingPathComponent("huggingface")
            .appendingPathComponent("hub")

        let modelFolder = "models--\(model.repoId.replacingOccurrences(of: "/", with: "--"))"
        let snapshotsDir = hubCache.appendingPathComponent(modelFolder).appendingPathComponent("snapshots")

        // Find the latest snapshot
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: snapshotsDir.path),
              let latestSnapshot = contents.sorted().last else {
            return nil
        }

        let modelPath = snapshotsDir.appendingPathComponent(latestSnapshot)
        let configPath = modelPath.appendingPathComponent("config.json")

        if FileManager.default.fileExists(atPath: configPath.path) {
            return modelPath
        }

        return nil
    }

    /// Find a model path (checks Hub cache first, then local directory)
    /// Only returns paths for complete downloads (all sharded files present)
    public static func findModelPath(for model: VoxtralModelInfo) -> URL? {
        // Check Hub cache first
        if let hubPath = hubCachePath(for: model) {
            let verification = verifyShardedModel(at: hubPath)
            if verification.complete {
                return hubPath
            }
        }

        // Check local models directory
        let localDir = localPath(for: model)
        if FileManager.default.fileExists(atPath: localDir.appendingPathComponent("config.json").path) {
            let verification = verifyShardedModel(at: localDir)
            if verification.complete {
                return localDir
            }
        }

        // Check project voxtral_models directory
        let projectModelsDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("voxtral_models")
            .appendingPathComponent(model.repoId.split(separator: "/").last.map(String.init) ?? model.id)
        if FileManager.default.fileExists(atPath: projectModelsDir.appendingPathComponent("config.json").path) {
            let verification = verifyShardedModel(at: projectModelsDir)
            if verification.complete {
                return projectModelsDir
            }
        }

        return nil
    }

    /// Get the directory URL for a model (for "Show in Finder").
    /// Returns the first existing path found, or the default local path.
    public static func modelDirectory(for model: VoxtralModelInfo) -> URL {
        findModelPath(for: model) ?? localPath(for: model)
    }

    /// Verify that a sharded model has all required safetensors files
    public static func verifyShardedModel(at path: URL) -> (complete: Bool, missing: [String]) {
        let incompleteFiles = incompleteAria2Files(at: path)
        let indexPath = path.appendingPathComponent("model.safetensors.index.json")

        // If no index file, it's either a single-file model or not sharded
        guard FileManager.default.fileExists(atPath: indexPath.path),
              let data = try? Data(contentsOf: indexPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let weightMap = json["weight_map"] as? [String: String] else {
            return (incompleteFiles.isEmpty, incompleteFiles)
        }

        // Get unique safetensors files from the weight map
        let requiredFiles = Set(weightMap.values)
        var missingFiles = incompleteFiles

        for filename in requiredFiles {
            let filePath = path.appendingPathComponent(filename)
            if !FileManager.default.fileExists(atPath: filePath.path) {
                missingFiles.append(filename)
            }
        }

        return (missingFiles.isEmpty, missingFiles)
    }

    private static func incompleteAria2Files(at path: URL) -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: path,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let basePath = path.resolvingSymlinksInPath().path
        var filenames: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "aria2" {
            let filePath = url.resolvingSymlinksInPath().path
            var relativePath = filePath.hasPrefix(basePath + "/")
                ? String(filePath.dropFirst(basePath.count + 1))
                : url.lastPathComponent
            relativePath.removeLast(".aria2".count)
            filenames.append("\(relativePath) (incomplete aria2 download)")
        }
        return filenames.sorted()
    }

    /// Download a model using Hub API
    public static func download(
        _ model: VoxtralModelInfo,
        progress: DownloadProgressCallback? = nil
    ) async throws -> URL {
        try ensureModelDirectories()

        // Check if already downloaded and complete
        if let existingPath = findModelPath(for: model) {
            let verification = verifyShardedModel(at: existingPath)
            if verification.complete {
                progress?(1.0, "Model already downloaded")
                return existingPath
            } else {
                print("Warning: Incomplete download detected. Missing files: \(verification.missing)")
                print("Re-downloading...")
            }
        }

        progress?(0.0, "Starting download of \(model.name)...")
        print("\nDownloading \(model.name) from HuggingFace...")
        print("Repository: \(model.repoId)")
        print()

        return try await downloadWithAria2(model, progress: progress)
    }

    /// Download a model by repo ID directly using aria2c
    public static func downloadByRepoId(
        _ repoId: String,
        progress: DownloadProgressCallback? = nil
    ) async throws -> URL {
        let model = VoxtralModelInfo(
            id: repoId.replacingOccurrences(of: "/", with: "--"),
            repoId: repoId,
            name: repoId,
            description: "",
            size: "Unknown",
            quantization: "Unknown",
            parameters: "Unknown",
            recommended: false
        )
        return try await download(model, progress: progress)
    }

    /// Resolve a model identifier to a local path, downloading if necessary
    public static func resolveModel(
        _ identifier: String,
        progress: DownloadProgressCallback? = nil
    ) async throws -> URL {
        // Try to find by ID first
        if let model = ModelRegistry.model(withId: identifier) {
            if let existingPath = findModelPath(for: model) {
                return existingPath
            }
            return try await download(model, progress: progress)
        }

        // Try to find by repo ID
        if let model = ModelRegistry.model(withRepoId: identifier) {
            if let existingPath = findModelPath(for: model) {
                return existingPath
            }
            return try await download(model, progress: progress)
        }

        // Check if it's a local path
        let localURL = URL(fileURLWithPath: identifier)
        if FileManager.default.fileExists(atPath: localURL.appendingPathComponent("config.json").path) {
            return localURL
        }

        // Try as a direct HuggingFace repo ID
        return try await downloadByRepoId(identifier, progress: progress)
    }

    /// Get the size of a downloaded model in bytes
    public static func modelSize(for model: VoxtralModelInfo) -> Int64? {
        guard let path = findModelPath(for: model) else { return nil }
        return directorySize(at: path)
    }

    /// Calculate directory size recursively
    private static func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
            return 0
        }

        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(fileSize)
            }
        }
        return totalSize
    }

    /// Format bytes as human-readable string
    public static func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// Delete a downloaded model
    public static func deleteModel(_ model: VoxtralModelInfo) throws {
        guard let path = findModelPath(for: model) else {
            throw ModelDownloaderError.modelNotFound
        }

        // Determine if it's in Hub cache (need to delete parent folder) or local directory
        let pathString = path.path

        if pathString.contains("/.cache/huggingface/hub/") {
            // Legacy Hub cache: delete the models--org--repo folder
            // path is .../snapshots/hash, so go up 2 levels
            let modelFolder = path.deletingLastPathComponent().deletingLastPathComponent()
            try FileManager.default.removeItem(at: modelFolder)
        } else if pathString.contains("/Library/Caches/models/") {
            // New Hub cache: delete the repo folder
            try FileManager.default.removeItem(at: path)
        } else {
            // Local directory
            try FileManager.default.removeItem(at: path)
        }
    }

    private struct HuggingFaceTreeItem: Decodable {
        struct LFSInfo: Decodable {
            let size: Int64?
        }

        let path: String
        let type: String?
        let size: Int64?
        let lfs: LFSInfo?

        var resolvedSize: Int64 {
            lfs?.size ?? size ?? 0
        }
    }

    private static func downloadWithAria2(
        _ model: VoxtralModelInfo,
        progress: DownloadProgressCallback? = nil
    ) async throws -> URL {
        guard let aria2cURL = findAria2cBinaryURL() else {
            throw ModelDownloaderError.aria2BinaryMissing
        }

        let modelPath = localPath(for: model)
        try FileManager.default.createDirectory(at: modelPath, withIntermediateDirectories: true)

        let files = try await fetchModelFiles(repoId: model.repoId)
        let filteredFiles = files.filter {
            guard $0.type == "file" else { return false }
            return $0.path.hasSuffix(".json")
                || $0.path.hasSuffix(".safetensors")
                || $0.path.hasSuffix(".txt")
        }

        guard !filteredFiles.isEmpty else {
            throw ModelDownloaderError.downloadFailed("No model files found in HuggingFace tree.")
        }

        // Ensure subdirectories exist for nested files
        for file in filteredFiles {
            let parent = modelPath.appendingPathComponent((file.path as NSString).deletingLastPathComponent)
            if parent.path != modelPath.path {
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            }
        }

        // Start aria2c as RPC daemon
        let port = UInt16.random(in: 49152...65000)
        let token = UUID().uuidString

        let process = Process()
        process.executableURL = aria2cURL
        process.arguments = [
            "--enable-rpc=true",
            "--rpc-listen-port=\(port)",
            "--rpc-secret=\(token)",
            "--rpc-listen-all=false",
            "--dir=\(modelPath.path)",
            "--continue=true",
            "--allow-overwrite=true",
            "--auto-file-renaming=false",
            "--max-concurrent-downloads=6",
            "--split=8",
            "--min-split-size=1M",
            "--summary-interval=0",
            "--console-log-level=warn",
            "--download-result=hide",
            "--check-certificate=false"
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        let client = Aria2RPCClient()
        await client.initialize(port: port, token: token)
        rpcClient = client
        daemonProcess = process
        activeGIDs = []
        downloadIntent = .active

        try process.run()

        // Wait for daemon to become ready
        var daemonReady = false
        for _ in 0..<30 {
            try await Task.sleep(for: .milliseconds(100))
            if let _ = try? await client.getVersion() {
                daemonReady = true
                break
            }
        }

        guard daemonReady else {
            process.terminate()
            daemonProcess = nil
            rpcClient = nil
            throw ModelDownloaderError.downloadFailed("aria2c RPC daemon failed to start.")
        }

        // Submit each file as a download via RPC
        var gids: [String] = []
        for file in filteredFiles {
            let encodedPath = encodePathForURL(file.path)
            let url = "https://huggingface.co/\(model.repoId)/resolve/main/\(encodedPath)?download=true"
            let gid = try await client.addUri([url], options: [
                "out": file.path
            ])
            gids.append(gid)
        }
        activeGIDs = gids

        progress?(0.0, "Downloading model files... 0%")

        // Poll RPC for progress
        while true {
            try await Task.sleep(for: .seconds(1))

            if downloadIntent != .active { break }

            let active = (try? await client.tellActive()) ?? []
            let waiting = (try? await client.tellWaiting()) ?? []
            let stopped = (try? await client.tellStopped()) ?? []

            let all = active + waiting + stopped

            var totalBytes: Int64 = 0
            var completedBytes: Int64 = 0
            var totalSpeed: Int64 = 0

            for status in all {
                totalBytes += Int64(status.totalLength) ?? 0
                completedBytes += Int64(status.completedLength) ?? 0
                totalSpeed += Int64(status.downloadSpeed) ?? 0
            }

            // Check for errors in stopped downloads
            for status in stopped {
                if status.status == "error" {
                    let msg = status.errorMessage ?? "Unknown error (code: \(status.errorCode ?? "?"))"
                    shutdownDaemon()
                    throw ModelDownloaderError.downloadFailed("aria2c download error: \(msg)")
                }
            }

            if totalBytes > 0 {
                let fraction = min(Double(completedBytes) / Double(totalBytes), 1.0)
                let percent = Int((fraction * 100).rounded())
                let speedBytesPerSecond: Double? = totalSpeed > 0 ? Double(totalSpeed) : nil
                let status = downloadStatus(percent: percent, speedBytesPerSecond: speedBytesPerSecond)
                progress?(fraction, status)
            }

            // All done when nothing is active or waiting
            if active.isEmpty && waiting.isEmpty { break }
        }

        shutdownDaemon()

        switch downloadIntent {
        case .paused:
            throw ModelDownloaderError.downloadPaused
        case .cancelled:
            try? FileManager.default.removeItem(at: modelPath)
            throw ModelDownloaderError.downloadCancelled
        case .active:
            break
        }

        let verification = verifyShardedModel(at: modelPath)
        guard verification.complete else {
            throw ModelDownloaderError.downloadFailed("Missing files after aria2c download: \(verification.missing.joined(separator: ", "))")
        }

        progress?(1.0, "Download complete!")
        return modelPath
    }

    private static func shutdownDaemon() {
        let client = rpcClient
        let process = daemonProcess
        Task { _ = try? await client?.forceShutdown() }
        if let process, process.isRunning { process.terminate() }
        daemonProcess = nil
        rpcClient = nil
        activeGIDs = []
    }

    private static func fetchModelFiles(repoId: String, subfolder: String? = nil) async throws -> [HuggingFaceTreeItem] {
        var urlString = "https://huggingface.co/api/models/\(repoId)/tree/main"
        if let subfolder {
            urlString += "/\(subfolder)"
        }
        urlString += "?recursive=1"

        guard let url = URL(string: urlString) else {
            throw ModelDownloaderError.downloadFailed("Invalid HuggingFace API URL.")
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw ModelDownloaderError.downloadFailed("HuggingFace API returned an invalid response.")
        }

        do {
            return try JSONDecoder().decode([HuggingFaceTreeItem].self, from: data)
        } catch {
            throw ModelDownloaderError.downloadFailed("Could not decode HuggingFace file list: \(error.localizedDescription)")
        }
    }

    private static func encodePathForURL(_ path: String) -> String {
        path
            .split(separator: "/")
            .map { component in
                String(component).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(component)
            }
            .joined(separator: "/")
    }

    private static func findAria2cBinaryURL() -> URL? {
        let candidateURLs: [URL] = [
            Bundle.main.resourceURL?.appendingPathComponent("Tools/aria2c"),
            Bundle.main.resourceURL?.appendingPathComponent("aria2c"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("petal/Resources/Tools/aria2c"),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".local/bin/aria2c"),
            URL(fileURLWithPath: "/opt/homebrew/bin/aria2c"),
            URL(fileURLWithPath: "/usr/local/bin/aria2c")
        ].compactMap { $0 }

        for url in candidateURLs where FileManager.default.isExecutableFile(atPath: url.path) {
            return url
        }

        return nil
    }

    private static var appDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("petal")
    }

    private static func ensureModelDirectories() throws {
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Convenience Methods for Default Model

    /// Check if the default/recommended model is downloaded
    public static func isDefaultModelDownloaded() -> Bool {
        findModelPath(for: ModelRegistry.defaultModel) != nil
    }

    /// Download the default/recommended model
    public static func downloadDefaultModel(
        progress: DownloadProgressCallback? = nil
    ) async throws -> URL {
        try await download(ModelRegistry.defaultModel, progress: progress)
    }

    private static func downloadStatus(percent: Int, speedBytesPerSecond: Double?) -> String {
        guard let speedBytesPerSecond, speedBytesPerSecond > 0 else {
            return "Downloading model files... \(percent)%"
        }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true

        let speed = formatter.string(fromByteCount: Int64(speedBytesPerSecond.rounded()))
        return "Downloading model files... \(percent)% (\(speed)/s)"
    }

    // MARK: - Generic HuggingFace Download

    /// Download files from a HuggingFace repository into a local directory using aria2c.
    ///
    /// - Parameters:
    ///   - repoId: HuggingFace repository (e.g. "argmaxinc/whisperkit-coreml").
    ///   - subfolder: Optional path inside the repo to scope the download (e.g. "f32").
    ///   - destination: Local directory to save files into.
    ///   - fileFilter: Predicate applied to each *local* relative path. `nil` accepts all files.
    ///   - progress: Callback receiving (fraction, status string) updates.
    public static func downloadFromHuggingFace(
        repoId: String,
        subfolder: String?,
        destination: URL,
        fileFilter: ((String) -> Bool)?,
        progress: DownloadProgressCallback?
    ) async throws {
        guard let aria2cURL = findAria2cBinaryURL() else {
            throw ModelDownloaderError.aria2BinaryMissing
        }

        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let files = try await fetchModelFiles(repoId: repoId, subfolder: subfolder)
        let prefix = subfolder.map { $0 + "/" } ?? ""

        let filteredFiles = files.filter { item in
            guard item.type == "file" else { return false }
            let localPath = prefix.isEmpty ? item.path : String(item.path.dropFirst(prefix.count))
            if let fileFilter {
                return fileFilter(localPath)
            }
            return true
        }

        guard !filteredFiles.isEmpty else {
            throw ModelDownloaderError.downloadFailed("No files found in HuggingFace tree for \(repoId).")
        }

        // Create subdirectories for nested files (e.g. .mlmodelc bundles)
        for file in filteredFiles {
            let localPath = prefix.isEmpty ? file.path : String(file.path.dropFirst(prefix.count))
            let parent = destination.appendingPathComponent((localPath as NSString).deletingLastPathComponent)
            if parent.path != destination.path {
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            }
        }

        // Start aria2c as RPC daemon
        let port = UInt16.random(in: 49152...65000)
        let token = UUID().uuidString

        let process = Process()
        process.executableURL = aria2cURL
        process.arguments = [
            "--enable-rpc=true",
            "--rpc-listen-port=\(port)",
            "--rpc-secret=\(token)",
            "--rpc-listen-all=false",
            "--dir=\(destination.path)",
            "--continue=true",
            "--allow-overwrite=true",
            "--auto-file-renaming=false",
            "--max-concurrent-downloads=6",
            "--split=8",
            "--min-split-size=1M",
            "--summary-interval=0",
            "--console-log-level=warn",
            "--download-result=hide",
            "--check-certificate=false"
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        let client = Aria2RPCClient()
        await client.initialize(port: port, token: token)
        rpcClient = client
        daemonProcess = process
        activeGIDs = []
        downloadIntent = .active

        try process.run()

        // Wait for daemon to become ready
        var daemonReady = false
        for _ in 0..<30 {
            try await Task.sleep(for: .milliseconds(100))
            if let _ = try? await client.getVersion() {
                daemonReady = true
                break
            }
        }

        guard daemonReady else {
            process.terminate()
            daemonProcess = nil
            rpcClient = nil
            throw ModelDownloaderError.downloadFailed("aria2c RPC daemon failed to start.")
        }

        // Submit each file as a download via RPC
        var gids: [String] = []
        for file in filteredFiles {
            let encodedPath = encodePathForURL(file.path)
            let url = "https://huggingface.co/\(repoId)/resolve/main/\(encodedPath)?download=true"
            let localPath = prefix.isEmpty ? file.path : String(file.path.dropFirst(prefix.count))
            let gid = try await client.addUri([url], options: [
                "out": localPath
            ])
            gids.append(gid)
        }
        activeGIDs = gids

        progress?(0.0, "Downloading model files... 0%")

        // Poll RPC for progress
        while true {
            try await Task.sleep(for: .seconds(1))

            if downloadIntent != .active { break }

            let active = (try? await client.tellActive()) ?? []
            let waiting = (try? await client.tellWaiting()) ?? []
            let stopped = (try? await client.tellStopped()) ?? []

            let all = active + waiting + stopped

            var totalBytes: Int64 = 0
            var completedBytes: Int64 = 0
            var totalSpeed: Int64 = 0

            for status in all {
                totalBytes += Int64(status.totalLength) ?? 0
                completedBytes += Int64(status.completedLength) ?? 0
                totalSpeed += Int64(status.downloadSpeed) ?? 0
            }

            // Check for errors in stopped downloads
            for status in stopped {
                if status.status == "error" {
                    let msg = status.errorMessage ?? "Unknown error (code: \(status.errorCode ?? "?"))"
                    shutdownDaemon()
                    throw ModelDownloaderError.downloadFailed("aria2c download error: \(msg)")
                }
            }

            if totalBytes > 0 {
                let fraction = min(Double(completedBytes) / Double(totalBytes), 1.0)
                let percent = Int((fraction * 100).rounded())
                let speedBytesPerSecond: Double? = totalSpeed > 0 ? Double(totalSpeed) : nil
                let status = downloadStatus(percent: percent, speedBytesPerSecond: speedBytesPerSecond)
                progress?(fraction, status)
            }

            // All done when nothing is active or waiting
            if active.isEmpty && waiting.isEmpty { break }
        }

        shutdownDaemon()

        switch downloadIntent {
        case .paused:
            throw ModelDownloaderError.downloadPaused
        case .cancelled:
            try? FileManager.default.removeItem(at: destination)
            throw ModelDownloaderError.downloadCancelled
        case .active:
            break
        }

        progress?(1.0, "Download complete!")
    }

    /// Delete the default/recommended model
    public static func deleteDefaultModel() throws {
        try deleteModel(ModelRegistry.defaultModel)
    }

    /// Get the default model info
    public static var defaultModel: VoxtralModelInfo {
        ModelRegistry.defaultModel
    }
}

/// Errors for model downloading
public enum ModelDownloaderError: LocalizedError, Equatable {
    case modelNotFound
    case downloadFailed(String)
    case aria2BinaryMissing
    case downloadPaused
    case downloadCancelled

    public var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "Model not found locally"
        case .downloadFailed(let reason):
            return "Download failed: \(reason)"
        case .aria2BinaryMissing:
            return "aria2c binary is missing from the app bundle or system PATH."
        case .downloadPaused:
            return "Download paused"
        case .downloadCancelled:
            return "Download cancelled"
        }
    }
}
