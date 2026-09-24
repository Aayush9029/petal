import Dependencies
import DownloadClient
import Foundation
import Observation
import LocalCleanupClient
import Shared

@MainActor
@Observable
public final class LocalCleanupDownloadModel {
    public var state: ModelDownloadState = .notDownloaded
    public var lastError: String?

    public let model: CleanupModel

    @ObservationIgnored @Dependency(\.localCleanupClient) private var localCleanupClient

    public init(model: CleanupModel) {
        self.model = model
    }

    public var sizeLabel: String { LocalCleanupClient.sizeLabel(for: model) ?? "" }

    public var modelDirectoryURL: URL? { localCleanupClient.modelDirectoryURL(model) }

    public func task() {
        guard !state.isActive else { return }
        state = localCleanupClient.isDownloaded(model) ? .downloaded : .notDownloaded
    }

    /// Replaces an outdated local copy. Cleanup keeps working until the old files are removed.
    public func updateIfOutdated() async {
        guard !state.isActive, localCleanupClient.isOutdated(model) else { return }
        state = .notDownloaded
        await downloadButtonTapped()
    }

    public func downloadButtonTapped() async {
        guard !state.isActive, !state.isDownloaded else { return }
        state = .preparing
        lastError = nil
        do {
            try await localCleanupClient.download(model) { [weak self] update in
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
        localCleanupClient.cancelDownload()
        state = .notDownloaded
    }

    public func deleteButtonTapped() async {
        do {
            try await localCleanupClient.deleteModel(model)
            state = .notDownloaded
            lastError = nil
        } catch {
            lastError = "\(model.displayName) could not be deleted: \(error.localizedDescription)"
        }
    }

    private func progressUpdated(_ update: DownloadProgress) {
        guard state.isActive else { return }
        state = .downloading(
            .init(fraction: update.fractionCompleted, statusText: update.status, speedText: update.speedText)
        )
    }
}
