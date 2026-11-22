import DownloadClient
import Foundation
import Shared

@DependencyClient
public struct LocalCleanupClient: Sendable {
    public var isDownloaded: @Sendable () -> Bool = { false }
    public var isOutdated: @Sendable () -> Bool = { false }
    public var download: @MainActor @Sendable (_ progress: @escaping @Sendable (ModelDownloadState.Progress) -> Void) async throws -> Void
    public var cancelDownload: @MainActor @Sendable () -> Void = {}
    public var deleteModel: @Sendable () async throws -> Void
    public var prepare: @Sendable () async throws -> Void
    public var clean: @Sendable (_ transcript: String) async throws -> String
    public var removeRetiredModels: @Sendable () async -> Void = {}
    public var unload: @Sendable () async -> Void = {}

    public static var sizeLabel: String { LocalCleanupModelFiles.info.size }
}

extension LocalCleanupClient: DependencyKey {
    public static var liveValue: Self {
        let runtime = LocalCleanupRuntime()
        return Self(
            isDownloaded: { LocalCleanupModelFiles.directory != nil },
            isOutdated: { LocalCleanupModelFiles.isOutdated },
            download: { progress in
                try await ModelTransfer.cleanup.run(progress: progress) { callback in
                    try await LocalCleanupModelFiles.install(progress: callback)
                    await runtime.unload()
                }
            },
            cancelDownload: { ModelTransfer.cleanup.cancel() },
            deleteModel: {
                await runtime.unload()
                try LocalCleanupModelFiles.delete()
            },
            prepare: { _ = try await runtime.prepare(directory: LocalCleanupModelFiles.directory) },
            clean: { try await runtime.clean($0, directory: LocalCleanupModelFiles.directory) },
            removeRetiredModels: {
                if let directory = LocalCleanupModelFiles.retiredDirectory {
                    try? FileManager.default.removeItem(at: directory)
                }
            },
            unload: { await runtime.unload() }
        )
    }

    public static let testValue = Self()
}

public extension DependencyValues {
    var localCleanupClient: LocalCleanupClient {
        get { self[LocalCleanupClient.self] }
        set { self[LocalCleanupClient.self] = newValue }
    }
}
