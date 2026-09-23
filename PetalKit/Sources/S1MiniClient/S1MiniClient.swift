import Dependencies
import DependenciesMacros
import DownloadClient
import Foundation
import Shared
import VoxtralCore

@DependencyClient
public struct S1MiniClient: Sendable {
    public var isDownloaded: @Sendable () -> Bool = { false }
    public var download: @Sendable (_ progress: @escaping @Sendable (DownloadProgress) -> Void) async throws -> Void
    public var cancelDownload: @Sendable () -> Void = {}
    public var modelDirectoryURL: @Sendable () -> URL? = { nil }
    public var deleteModel: @Sendable () async throws -> Void
    /// Loads the weights so the first cleanup after a recording skips the ~0.2 s load.
    public var prepare: @Sendable () async throws -> Void
    public var clean: @Sendable (_ transcript: String, _ controls: S1MiniControls) async throws -> S1MiniCleanup
    public var unload: @Sendable () async -> Void = {}
}

extension S1MiniClient: DependencyKey {
    public static let sizeLabel = "619 MB"

    public static var liveValue: Self {
        let runtime = S1MiniRuntime()
        return Self(
            isDownloaded: { S1MiniModelFiles.directory != nil },
            download: { progress in
                do {
                    _ = try await ModelDownloader.download(S1MiniModelFiles.info) { fraction, status in
                        progress(DownloadProgress(fractionCompleted: min(max(fraction, 0), 1), status: status, speedText: nil))
                    }
                } catch let error as ModelDownloaderError {
                    throw DownloadClientFailure(error)
                }
            },
            cancelDownload: { ModelDownloader.cancelDownload() },
            modelDirectoryURL: { S1MiniModelFiles.directory },
            deleteModel: {
                await runtime.unload()
                if let directory = S1MiniModelFiles.directory {
                    try FileManager.default.removeItem(at: directory)
                }
            },
            prepare: { _ = try await runtime.prepare() },
            clean: { transcript, controls in
                try await runtime.clean(transcript, controls: controls)
            },
            unload: { await runtime.unload() }
        )
    }

    public static var testValue: Self { Self() }
}

public extension DependencyValues {
    var s1MiniClient: S1MiniClient {
        get { self[S1MiniClient.self] }
        set { self[S1MiniClient.self] = newValue }
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
