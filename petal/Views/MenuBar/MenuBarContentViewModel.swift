import AppKit
import Dependencies
import HistoryClient
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

    private let appModel: AppModel
    private var updatesModel: CheckForUpdatesModel?
    @ObservationIgnored @Dependency(\.historyClient) private var historyClient

    init(appModel: AppModel, updatesModel: CheckForUpdatesModel? = nil) {
        self.appModel = appModel
        self.updatesModel = updatesModel
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
        return transientMessage ?? appModel.statusTitle
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
        Array(
            appModel.recentTranscriptHistoryEntries
            .compactMap { entry in
                guard let transcript = historyClient.transcriptText(entry.preferredTranscriptRelativePath) else { return nil }
                let normalizedTranscript = transcript
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalizedTranscript.isEmpty else { return nil }

                let title = String(normalizedTranscript.prefix(112))

                return HistoryMenuItem(
                    id: entry.id,
                    title: title
                )
            }
        )
    }

    var showsCheckForUpdates: Bool { updatesModel != nil }
    var canCheckForUpdates: Bool { updatesModel?.canCheckForUpdates == true }

    func setUpdatesModel(_ updatesModel: CheckForUpdatesModel?) {
        self.updatesModel = updatesModel
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

    func startRecording() {
        Task { await appModel.handleDeepLink(.start) }
    }

    func stopRecording() {
        Task { await appModel.handleDeepLink(.stop) }
    }

    func checkForUpdates() {
        updatesModel?.checkForUpdates()
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
