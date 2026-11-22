import Dependencies
import DownloadClient
import Foundation
import Observation
import Shared

@MainActor
@Observable
public final class ModelDownloadModel {
    @ObservationIgnored @Shared(.selectedModelID) public var selectedModelID

    public var state: ModelDownloadState = .notDownloaded
    public var lastError: String?
    public var onDownloadCompleted: (@MainActor (ModelOption) -> Void)?

    public private(set) var downloadingModelOption: ModelOption?
    public private(set) var deletingModelOptions: Set<ModelOption> = []

    @ObservationIgnored @Dependency(\.downloadClient) private var downloadClient

    @ObservationIgnored private var attempt = 0

    public init() {}

    public func task() {
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
        guard state.isActive || state.isPaused else { return }
        attempt += 1
        downloadClient.cancelDownload()
        resetToIdle()
    }

    public func isModelDownloaded(_ option: ModelOption) -> Bool {
        guard !deletingModelOptions.contains(option) else { return false }
        return downloadClient.isModelDownloaded(option)
    }

    public func isDeletingModel(_ option: ModelOption) -> Bool {
        deletingModelOptions.contains(option)
    }

    public func deleteModel(_ option: ModelOption) async {
        guard option.requiresDownload else { return }
        guard !deletingModelOptions.contains(option) else { return }

        deletingModelOptions.insert(option)
        if option.rawValue == selectedModelID {
            state = .notDownloaded
        }

        do {
            try await downloadClient.deleteModel(option)
            deletingModelOptions.remove(option)
            if option.rawValue == selectedModelID {
                state = .notDownloaded
            }
            lastError = nil
        } catch {
            deletingModelOptions.remove(option)
            if option.rawValue == selectedModelID {
                refreshDownloadStateForSelectedModel()
            }
            lastError = "Failed to delete model: \(error.localizedDescription)"
        }
    }

    public func selectedModelChanged() {
        lastError = nil

        if state.isActive || state.isPaused { return }
        refreshDownloadStateForSelectedModel()
    }

    private func startDownload(_ option: ModelOption?) async {
        guard let option else {
            let message = "Select a model to continue."
            state = .failed(message)
            lastError = message
            return
        }

        guard !state.isActive else { return }
        guard !deletingModelOptions.contains(option) else { return }

        attempt += 1
        let current = attempt
        downloadingModelOption = option
        state = .preparing
        lastError = nil

        do {
            try await downloadClient.downloadModel(option) { [weak self] update in
                Task { @MainActor [weak self] in
                    guard let self, attempt == current, state.isActive else { return }
                    state = .downloading(update)
                }
            }

            guard attempt == current else { return }
            downloadingModelOption = nil
            if option == selectedModelOption {
                state = .downloaded
            } else {
                refreshDownloadStateForSelectedModel()
            }
            onDownloadCompleted?(option)
            lastError = nil
        } catch {
            guard attempt == current else { return }
            if error is CancellationError {
                resetToIdle()
            } else {
                handleDownloadFailure(error as? DownloadClientFailure ?? .failed(error.localizedDescription))
            }
        }
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
        state = isSelectedModelDownloaded ? .downloaded : .notDownloaded
    }

    private func resetToIdle() {
        downloadingModelOption = nil
        refreshDownloadStateForSelectedModel()
        lastError = nil
    }
}
