import Foundation
import Shared
import VoxtralCore

public enum DownloadClientFailure: LocalizedError, Sendable, Equatable {
    case paused
    case cancelled
    case aria2BinaryMissing
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .paused: "Download paused"
        case .cancelled: "Download cancelled"
        case .aria2BinaryMissing: "aria2c binary is missing from the app bundle or system PATH."
        case let .failed(message): message
        }
    }

    package init(_ error: ModelDownloaderError) {
        switch error {
        case .downloadPaused: self = .paused
        case .downloadCancelled: self = .cancelled
        case .aria2BinaryMissing: self = .aria2BinaryMissing
        case let .downloadFailed(message): self = .failed(message)
        case .modelNotFound: self = .failed(error.localizedDescription)
        }
    }
}

@DependencyClient
public struct DownloadClient: Sendable {
    public var downloadModel: @MainActor @Sendable (ModelOption, @escaping @Sendable (ModelDownloadState.Progress) -> Void) async throws -> Void
    public var pauseDownload: @MainActor @Sendable () -> Void = {}
    public var cancelDownload: @MainActor @Sendable () -> Void = {}
    public var modelDirectoryURL: @Sendable (ModelOption) -> URL? = { _ in nil }
    public var deleteModel: @Sendable (ModelOption) async throws -> Void

    public func isModelDownloaded(_ option: ModelOption) -> Bool {
        !option.requiresDownload || modelDirectoryURL(option) != nil
    }
}

extension DownloadClient: DependencyKey {
    public static var liveValue: Self {
        Self(
            downloadModel: { option, progress in
                guard let files = SpeechModelFiles(option) else {
                    progress(.init(fraction: 1, statusText: "No download required for this model."))
                    return
                }
                try await ModelTransfer.speech.run(progress: progress) { callback in
                    try await files.download(repoID: option.descriptor.repoID, progress: callback)
                }
            },
            pauseDownload: { ModelTransfer.speech.pause() },
            cancelDownload: { ModelTransfer.speech.cancel() },
            modelDirectoryURL: { SpeechModelFiles($0)?.installedDirectory },
            deleteModel: { option in
                guard let files = SpeechModelFiles(option) else { return }
                let directory = files.installedDirectory ?? files.directory
                guard FileManager.default.fileExists(atPath: directory.path) else { return }
                try FileManager.default.removeItem(at: directory)
            }
        )
    }

    public static let testValue = Self()
}

public extension DependencyValues {
    var downloadClient: DownloadClient {
        get { self[DownloadClient.self] }
        set { self[DownloadClient.self] = newValue }
    }
}
