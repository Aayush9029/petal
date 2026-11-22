import Foundation
import Dependencies
import HistoryClient
import ModelDownloadFeature
import Observation
import Shared

@MainActor
@Observable
public final class MenuBarContentViewModel {
    public struct HistoryMenuItem: Identifiable, Sendable {
        public let id: UUID
        public let title: String
    }

    public struct DownloadStatus: Equatable {
        public var fraction: Double?
        public var isPaused: Bool
    }

    // The hosting view survives orderOut, so the panel reports its visibility explicitly.
    public var isPopupVisible = false

    private let appModel: AppModel
    @ObservationIgnored @Dependency(\.historyClient) private var historyClient
    public private(set) var historyMenuItems: [HistoryMenuItem] = []

    public init(appModel: AppModel) {
        self.appModel = appModel
    }

    public var statusTitle: String { appModel.statusTitle }
    public var iconState: MenuBarIconState { appModel.menuBarIconState }
    public var audioLevel: Double { appModel.currentLevel }
    public var isRecording: Bool {
        if case .recording = appModel.sessionState {
            return true
        }
        return false
    }

    public var statusHeadline: String {
        if let statusErrorMessage { return statusErrorMessage }
        if isRecording { return "Recording" }
        if let downloadHeadline { return downloadHeadline }
        if let message = appModel.menuTransientMessage { return message }
        if appModel.isWarmingModel { return "Warming up \(appModel.selectedModelOption?.displayName ?? "model")…" }
        return appModel.statusTitle
    }

    public var downloadStatus: DownloadStatus? {
        switch appModel.modelDownloadViewModel.state {
        case .preparing:
            DownloadStatus(fraction: nil, isPaused: false)
        case let .downloading(progress):
            DownloadStatus(fraction: progress.fraction, isPaused: false)
        case let .paused(progress):
            DownloadStatus(fraction: progress.fraction, isPaused: true)
        case .notDownloaded, .downloaded, .failed:
            nil
        }
    }

    private var downloadHeadline: String? {
        guard let downloadStatus else { return nil }
        let downloads = appModel.modelDownloadViewModel
        let name = (downloads.downloadingModelOption ?? appModel.selectedModelOption)?.displayName ?? "model"
        guard let fraction = downloadStatus.fraction else { return "Preparing \(name)…" }
        let percent = fraction.formatted(.percent.precision(.fractionLength(0)))
        if downloadStatus.isPaused { return "Download paused at \(percent)" }
        if let speed = downloads.state.progress?.speedText {
            return "Downloading \(name), \(percent) at \(speed)"
        }
        return "Downloading \(name), \(percent)"
    }

    private var statusErrorMessage: String? {
        guard case let .error(message) = appModel.sessionState else { return nil }
        return message
    }

    public var shouldShowPermissionsSection: Bool { needsMicrophonePermission || needsAccessibilityPermission }

    public var needsMicrophonePermission: Bool { !appModel.microphoneAuthorized }
    public var needsAccessibilityPermission: Bool { !appModel.accessibilityAuthorized }

    public var shouldShowHistoryMenu: Bool {
        appModel.historyRetentionMode.keepsHistory
    }

    public var visibleHistoryEntries: [TranscriptHistoryEntry]? {
        guard isPopupVisible, shouldShowHistoryMenu else { return nil }
        return appModel.recentTranscriptHistoryEntries
    }

    public func loadHistoryMenu() async {
        guard let entries = visibleHistoryEntries else { return }
        let contents = await historyClient.entryContents(entries)
        guard !Task.isCancelled, entries == visibleHistoryEntries else { return }
        historyMenuItems = entries.compactMap { entry in
            guard let content = contents[entry.id],
                  let text = entry.cleanupVariant == nil ? content.transcript : content.cleanup
            else { return nil }
            let title = text.replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            return HistoryMenuItem(id: entry.id, title: String(title.prefix(112)))
        }
    }

    public func requestMicrophonePermission() {
        Task { await appModel.microphonePermissionButtonTapped() }
    }

    public func requestAccessibilityPermission() {
        appModel.accessibilityPermissionButtonTapped()
    }

    public func copyHistoryEntry(_ entryID: UUID) {
        appModel.copyTranscriptHistoryButtonTapped(entryID)
    }

    public func deleteHistoryEntry(_ entryID: UUID) {
        appModel.deleteTranscriptHistoryButtonTapped(entryID)
    }

    public func audioFilesDropped(_ urls: [URL]) async {
        await appModel.audioFilesDropped(urls)
    }

    public func startRecording() {
        Task { await appModel.handleDeepLink(.start) }
    }

    public func stopRecording() {
        Task { await appModel.handleDeepLink(.stop) }
    }

    public func openSettings() {
        appModel.openSettingsWindow()
    }
}
