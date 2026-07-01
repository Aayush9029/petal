import Dependencies
import DownloadClient
import Foundation
import Observation
import Shared

@MainActor
@Observable
public final class ModelDownloadModel {
    @ObservationIgnored @Shared(.selectedModelID) public var selectedModelID = ModelOption.defaultOption.rawValue

    public var state: ModelDownloadState = .notDownloaded
    public var lastError: String?
    public var transientMessage: String?
    public var onDownloadCompleted: (@MainActor () -> Void)?

    public private(set) var downloadingModelOption: ModelOption?

    @ObservationIgnored @Dependency(\.downloadClient) private var downloadClient

    public init(isPreviewMode: Bool = false) {
        if isPreviewMode {
            $selectedModelID.withLock { $0 = ModelOption.defaultOption.rawValue }
            return
        }

        $selectedModelID.withLock { $0 = ModelOption.from(modelID: $0).rawValue }
        refreshDownloadStateForSelectedModel()
    }

    public var selectedModelOption: ModelOption? {
        ModelOption(rawValue: selectedModelID)
    }

    public var isSelectedModelDownloaded: Bool {
        guard let selectedModelOption else { return false }
        return isModelDownloaded(selectedModelOption)
    }

    public var modelDirectoryURL: URL? {
        guard let option = selectedModelOption else { return nil }
        return downloadClient.modelDirectoryURL(option)
    }

    public func downloadButtonTapped() async {
        await startDownload(selectedModelOption)
    }

    public func downloadModel(_ option: ModelOption) async {
        await startDownload(option)
    }

    public func pauseButtonTapped() {
        guard state.isActive else { return }
        downloadClient.pauseDownload()
        state = .paused(state.progress ?? .init(fraction: 0, statusText: "Download paused"))
    }

    public func resumeButtonTapped() async {
        guard state.isPaused else { return }
        await startDownload(downloadingModelOption ?? selectedModelOption)
    }

    public func cancelButtonTapped() {
        downloadClient.cancelDownload()
        resetToIdle()
    }

    public func deleteModelButtonTapped() async {
        guard let option = selectedModelOption else { return }
        await deleteModel(option)
    }

    public func isModelDownloaded(_ option: ModelOption) -> Bool {
        guard option.requiresDownload else { return true }
        return downloadClient.isModelDownloaded(option)
    }

    public func deleteModel(_ option: ModelOption) async {
        guard option.requiresDownload else { return }
        do {
            try await downloadClient.deleteModel(option)
            if option.rawValue == selectedModelID {
                state = .notDownloaded
            }
        } catch {
            lastError = "Failed to delete model: \(error.localizedDescription)"
        }
    }

    public func selectedModelChanged() {
        transientMessage = nil
        lastError = nil

        if state.isActive || state.isPaused { return }
        refreshDownloadStateForSelectedModel()
    }

    public func downloadModel() async {
        await downloadButtonTapped()
    }

    public func pauseDownload() {
        pauseButtonTapped()
    }

    public func resumeDownload() async {
        await resumeButtonTapped()
    }

    public func cancelDownload() {
        cancelButtonTapped()
    }

    private func startDownload(_ option: ModelOption?) async {
        guard let option else {
            let message = "Select a model to continue."
            state = .failed(message)
            lastError = message
            return
        }

        guard !state.isActive else { return }

        downloadingModelOption = option
        state = .preparing
        transientMessage = nil
        lastError = nil

        do {
            try await downloadClient.downloadModel(option) { [weak self] update in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    applyProgressUpdate(update)
                }
            }

            state = .downloaded
            downloadingModelOption = nil
            if option.rawValue == selectedModelID {
                onDownloadCompleted?()
            }
            transientMessage = "Model ready. Click Finish Setup to continue."
            lastError = nil
        } catch is CancellationError {
            downloadingModelOption = nil
        } catch let error as DownloadClientFailure {
            handleDownloadFailure(error)
        } catch {
            handleDownloadFailure(.failed(error.localizedDescription))
        }
    }

    private func applyProgressUpdate(_ update: DownloadProgress) {
        if state.isPaused { return }

        let fraction = min(max(update.fractionCompleted, 0), 1)
        let progress = ModelDownloadState.Progress(
            fraction: fraction,
            statusText: update.status,
            speedText: update.speedText
        )
        state = .downloading(progress)
    }

    private func handleDownloadFailure(_ failure: DownloadClientFailure) {
        switch failure {
        case .paused:
            let progress = state.progress ?? .init(fraction: 0, statusText: "Download paused")
            state = .paused(.init(fraction: progress.fraction, statusText: "Download paused"))
            lastError = nil
        case .cancelled:
            resetToIdle()
        case .aria2BinaryMissing, .failed:
            let message = failure.errorDescription ?? "Download failed."
            state = .failed(message)
            lastError = message
        }
    }

    private func refreshDownloadStateForSelectedModel() {
        if isSelectedModelDownloaded {
            state = .downloaded
        } else {
            state = .notDownloaded
        }
    }

    private func resetToIdle() {
        downloadingModelOption = nil
        state = .notDownloaded
        lastError = nil
    }
}
