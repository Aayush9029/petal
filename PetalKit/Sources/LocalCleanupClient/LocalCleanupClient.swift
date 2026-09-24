import Dependencies
import DependenciesMacros
import DownloadClient
import Foundation
import Shared
import VoxtralCore

/// On-device transcript cleanup models (S1-mini and Petal W1) that run through MLX.
@DependencyClient
public struct LocalCleanupClient: Sendable {
    public var isDownloaded: @Sendable (_ model: CleanupModel) -> Bool = { _ in false }
    /// A local copy exists but is older than the version this app expects.
    public var isOutdated: @Sendable (_ model: CleanupModel) -> Bool = { _ in false }
    public var download: @Sendable (_ model: CleanupModel, _ progress: @escaping @Sendable (DownloadProgress) -> Void) async throws -> Void
    public var cancelDownload: @Sendable () -> Void = {}
    public var modelDirectoryURL: @Sendable (_ model: CleanupModel) -> URL? = { _ in nil }
    public var deleteModel: @Sendable (_ model: CleanupModel) async throws -> Void
    /// Loads the weights so the first cleanup after a recording skips the load.
    public var prepare: @Sendable (_ model: CleanupModel) async throws -> Void
    public var clean: @Sendable (_ transcript: String, _ model: CleanupModel, _ controls: S1MiniControls) async throws -> LocalCleanupResult
    public var unload: @Sendable () async -> Void = {}
}

extension LocalCleanupClient: DependencyKey {
    public static func sizeLabel(for model: CleanupModel) -> String? {
        LocalCleanupModelFiles.info(for: model)?.size
    }

    public static var liveValue: Self {
        let runtime = LocalCleanupRuntime()
        return Self(
            isDownloaded: { LocalCleanupModelFiles.directory(for: $0) != nil },
            isOutdated: { LocalCleanupModelFiles.isOutdated($0) },
            download: { model, progress in
                guard let info = LocalCleanupModelFiles.info(for: model) else { return }
                if LocalCleanupModelFiles.isOutdated(model), let directory = LocalCleanupModelFiles.directory(for: model) {
                    await runtime.unload()
                    try FileManager.default.removeItem(at: directory)
                }
                do {
                    _ = try await ModelDownloader.download(info) { fraction, status in
                        progress(DownloadProgress(fractionCompleted: min(max(fraction, 0), 1), status: status, speedText: nil))
                    }
                    LocalCleanupModelFiles.recordRevision(for: model)
                } catch let error as ModelDownloaderError {
                    throw DownloadClientFailure(error)
                }
            },
            cancelDownload: { ModelDownloader.cancelDownload() },
            modelDirectoryURL: { LocalCleanupModelFiles.directory(for: $0) },
            deleteModel: { model in
                await runtime.unload()
                if let directory = LocalCleanupModelFiles.directory(for: model) {
                    try FileManager.default.removeItem(at: directory)
                }
            },
            prepare: { model in _ = try await runtime.prepare(directory: LocalCleanupModelFiles.directory(for: model)) },
            clean: { transcript, model, controls in
                try await runtime.clean(transcript, model: model, controls: controls, directory: LocalCleanupModelFiles.directory(for: model))
            },
            unload: { await runtime.unload() }
        )
    }

    public static var testValue: Self { Self() }
}

public extension DependencyValues {
    var localCleanupClient: LocalCleanupClient {
        get { self[LocalCleanupClient.self] }
        set { self[LocalCleanupClient.self] = newValue }
    }
}

private extension DownloadClientFailure {
    init(_ error: ModelDownloaderError) {
        switch error {
        case .downloadPaused: self = .paused
        case .downloadCancelled: self = .cancelled
        case .aria2BinaryMissing: self = .aria2BinaryMissing
        case let .downloadFailed(message): self = .failed(message)
        case .modelNotFound: self = .failed(error.localizedDescription)
        }
    }
}
