import AppKit
import Dependencies
import HistoryClient
import ModelDownloadFeature
import Observation
import Shared
import SwiftUI

@MainActor
@Observable
final class MenuBarContentViewModel {
    struct HistoryMenuItem: Identifiable {
        let id: UUID
        let title: String
    }

    struct DownloadStatus: Equatable {
        /// Nil until the download reports its size.
        var fraction: Double?
        var isPaused: Bool
    }

    private struct CachedTitle {
        var relativePath: String?
        var title: String?
    }

    /// The popup's hosting view outlives `orderOut`, so animations check this to stop while it is hidden.
    var isPopupVisible = false

    private let appModel: AppModel
    @ObservationIgnored @Dependency(\.historyClient) private var historyClient
    /// A transcript file read costs a disk access, and the popup asks for the titles on each status change.
    @ObservationIgnored private var titleCache: [UUID: CachedTitle] = [:]

    init(appModel: AppModel) {
        self.appModel = appModel
    }

    var statusTitle: String { appModel.statusTitle }
    var iconState: MenuBarIconState { appModel.menuBarIconState }
    /// Read per animation frame, deliberately outside observation so level changes don't re-run the status pass.
    var audioLevel: Double { appModel.currentLevel }
    var isRecording: Bool {
        if case .recording = appModel.sessionState {
            return true
        }
        return false
    }

    /// Leads with the current state, so the popup's status line never goes blank and never changes the panel's height.
    var statusHeadline: String {
        if let statusErrorMessage { return statusErrorMessage }
        if isRecording { return "Recording" }
        if let downloadHeadline { return downloadHeadline }
        return transientMessage ?? appModel.statusTitle
    }

    var downloadStatus: DownloadStatus? {
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

    private var transientMessage: String? {
        guard let message = appModel.transientMessage else { return nil }
        let lower = message.lowercased()
        let allowedKeywords = [
            "accessibility",
            "microphone",
            "setup",
            "turn on",
            "warming",
            "preparing",
            "downloading",
            "failed"
        ]
        return allowedKeywords.contains(where: { lower.contains($0) }) ? message : nil
    }

    var shouldShowPermissionsSection: Bool {
        !appModel.microphoneAuthorized || !appModel.accessibilityAuthorized
    }

    var needsMicrophonePermission: Bool { !appModel.microphoneAuthorized }
    var needsAccessibilityPermission: Bool { !appModel.accessibilityAuthorized }

    var shouldShowHistoryMenu: Bool {
        appModel.historyRetentionMode.keepsHistory
    }

    var historyMenuItems: [HistoryMenuItem] {
        let entries = appModel.recentTranscriptHistoryEntries
        var cache: [UUID: CachedTitle] = [:]
        var items: [HistoryMenuItem] = []
        for entry in entries {
            let relativePath = entry.preferredTranscriptRelativePath
            var cached = titleCache[entry.id]
            if cached?.relativePath != relativePath || cached == nil {
                cached = CachedTitle(relativePath: relativePath, title: title(relativePath: relativePath))
            }
            cache[entry.id] = cached
            if let title = cached?.title {
                items.append(HistoryMenuItem(id: entry.id, title: title))
            }
        }
        titleCache = cache
        return items
    }

    private func title(relativePath: String?) -> String? {
        guard let transcript = historyClient.transcriptText(relativePath) else { return nil }
        let normalized = transcript
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : String(normalized.prefix(112))
    }

    func requestMicrophonePermission() {
        Task { await appModel.microphonePermissionButtonTapped() }
    }

    func requestAccessibilityPermission() {
        appModel.accessibilityPermissionButtonTapped()
    }

    func copyHistoryEntry(_ entryID: UUID) {
        appModel.copyTranscriptHistoryButtonTapped(entryID)
    }

    func deleteHistoryEntry(_ entryID: UUID) {
        appModel.deleteTranscriptHistoryButtonTapped(entryID)
    }

    func audioFilesDropped(_ urls: [URL]) async {
        switch AudioFileDropValidator.validate(urls) {
        case let .accepted(url):
            await appModel.transcribeDroppedAudioFile(url)
        case let .rejected(error):
            appModel.droppedAudioFileRejected(error)
        }
    }

    func chooseAudioFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = AudioFileDropValidator.supportedContentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor [weak self] in
                await self?.audioFilesDropped([url])
            }
        }
    }

    func startRecording() {
        Task { await appModel.handleDeepLink(.start) }
    }

    func stopRecording() {
        Task { await appModel.handleDeepLink(.stop) }
    }

    func showAbout() {
        NSApp.sendAction(#selector(AppDelegate.showAboutPanel), to: nil, from: nil)
    }

    func openSettings() {
        appModel.openSettingsWindow()
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }
}
