import DownloadClient
import LocalCleanupClient
import Observation
import Shared

@MainActor
@Observable
public final class LocalCleanupDownloadModel {
    public var state: ModelDownloadState = .notDownloaded

    @ObservationIgnored @Dependency(\.localCleanupClient) private var localCleanupClient
    @ObservationIgnored private var attempt = 0

    public init() {}

    public var sizeLabel: String { LocalCleanupClient.sizeLabel }

    public func task() {
        guard !state.isActive else { return }
        state = localCleanupClient.isDownloaded() ? .downloaded : .notDownloaded
    }

    public func updateIfOutdated() async {
        guard !state.isActive, localCleanupClient.isOutdated() else { return }
        state = .notDownloaded
        await downloadButtonTapped()
    }

    public func downloadButtonTapped() async {
        guard !state.isActive, !state.isDownloaded else { return }
        attempt += 1
        let current = attempt
        state = .preparing
        do {
            try await localCleanupClient.download { [weak self] update in
                Task { @MainActor [weak self] in
                    guard let self, attempt == current, state.isActive else { return }
                    state = .downloading(update)
                }
            }
            guard attempt == current else { return }
            state = .downloaded
        } catch {
            guard attempt == current else { return }
            switch error {
            case DownloadClientFailure.cancelled, DownloadClientFailure.paused, is CancellationError:
                state = localCleanupClient.isDownloaded() ? .downloaded : .notDownloaded
            default:
                state = .failed(error.localizedDescription)
            }
        }
    }

    public func cancelButtonTapped() {
        guard state.isActive else { return }
        attempt += 1
        localCleanupClient.cancelDownload()
        state = localCleanupClient.isDownloaded() ? .downloaded : .notDownloaded
    }

    public func deleteButtonTapped() async {
        guard !state.isActive else { return }
        do {
            try await localCleanupClient.deleteModel()
            state = .notDownloaded
        } catch {
            state = .failed("\(CleanupModel.petalW1.displayName) could not be deleted: \(error.localizedDescription)")
        }
    }
}
