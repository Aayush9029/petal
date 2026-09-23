import Dependencies
import DownloadClient
import Foundation
import Observation
import S1MiniClient
import Shared

@MainActor
@Observable
public final class S1MiniDownloadModel {
    public var state: ModelDownloadState = .notDownloaded
    public var lastError: String?

    @ObservationIgnored @Dependency(\.s1MiniClient) private var s1MiniClient

    public init() {}

    public var sizeLabel: String { S1MiniClient.sizeLabel }

    public var modelDirectoryURL: URL? { s1MiniClient.modelDirectoryURL() }

    public func task() {
        guard !state.isActive else { return }
        state = s1MiniClient.isDownloaded() ? .downloaded : .notDownloaded
    }

    public func downloadButtonTapped() async {
        guard !state.isActive, !state.isDownloaded else { return }
        state = .preparing
        lastError = nil
        do {
            try await s1MiniClient.download { [weak self] update in
                Task { @MainActor [weak self] in
                    self?.progressUpdated(update)
                }
            }
            state = .downloaded
        } catch DownloadClientFailure.cancelled, DownloadClientFailure.paused {
            state = .notDownloaded
        } catch is CancellationError {
            state = .notDownloaded
        } catch {
            let message = error.localizedDescription
            state = .failed(message)
            lastError = message
        }
    }

    public func cancelButtonTapped() {
        s1MiniClient.cancelDownload()
        state = .notDownloaded
    }

    public func deleteButtonTapped() async {
        do {
            try await s1MiniClient.deleteModel()
            state = .notDownloaded
            lastError = nil
        } catch {
            lastError = "S1-mini could not be deleted: \(error.localizedDescription)"
        }
    }

    private func progressUpdated(_ update: DownloadProgress) {
        guard state.isActive else { return }
        state = .downloading(
            .init(fraction: update.fractionCompleted, statusText: update.status, speedText: update.speedText)
        )
    }
}
