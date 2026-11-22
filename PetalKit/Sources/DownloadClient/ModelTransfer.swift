import Foundation
import Shared
import VoxtralCore

// The vendored downloader has one process-wide aria2 daemon and one cancellation flag.
@MainActor
package final class ModelTransfer {
    package static let speech = ModelTransfer()
    package static let cleanup = ModelTransfer()

    private static var tail: Task<Void, any Error>?
    private var latest: LockIsolated<DownloadClientFailure?>?
    private var running: LockIsolated<DownloadClientFailure?>?

    package func run(
        progress: @escaping @Sendable (ModelDownloadState.Progress) -> Void,
        operation: @escaping @Sendable (@escaping DownloadProgressCallback) async throws -> Void
    ) async throws {
        let previous = Self.tail
        let stopReason = LockIsolated<DownloadClientFailure?>(nil)
        latest = stopReason
        let task = Task {
            _ = await previous?.result
            if let reason = stopReason.value { throw reason }
            running = stopReason
            defer { running = nil }
            do {
                try await operation { fraction, status in
                    // The daemon resets its intent after fetching the remote file list.
                    if let reason = stopReason.value {
                        Self.stopDaemon(reason)
                    } else {
                        progress(.init(fraction: fraction, statusText: status))
                    }
                }
            } catch {
                if let reason = stopReason.value { throw reason }
                if let error = error as? ModelDownloaderError { throw DownloadClientFailure(error) }
                throw error
            }
            if let reason = stopReason.value { throw reason }
        }
        Self.tail = task
        defer {
            if latest === stopReason { latest = nil }
            if Self.tail == task { Self.tail = nil }
        }
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            Task { @MainActor in self.stop(.cancelled, attempt: stopReason) }
        }
    }

    package func pause() { stop(.paused, attempt: latest) }
    package func cancel() { stop(.cancelled, attempt: latest) }

    private func stop(_ reason: DownloadClientFailure, attempt: LockIsolated<DownloadClientFailure?>?) {
        guard let attempt else { return }
        attempt.setValue(reason)
        if running === attempt { Self.stopDaemon(reason) }
    }

    private nonisolated static func stopDaemon(_ reason: DownloadClientFailure) {
        if reason == .paused { ModelDownloader.pauseDownload() }
        else { ModelDownloader.cancelDownload() }
    }
}
