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
        let subtitle: String
    }

    private let appModel: AppModel
    private var updatesModel: CheckForUpdatesModel?
    @ObservationIgnored @Dependency(\.historyClient) private var historyClient

    init(appModel: AppModel, updatesModel: CheckForUpdatesModel? = nil) {
        self.appModel = appModel
        self.updatesModel = updatesModel
    }

    var statusTitle: String { appModel.statusTitle }
    var statusSymbolName: String { appModel.menuBarSymbolName }
    var iconState: MenuBarIconState { appModel.menuBarIconState }
    /// Smoothed input level for the recording pulse. Read per animation frame,
    /// intentionally outside observation so level changes don't re-run status.
    var audioLevel: Double { appModel.currentLevel }
    var isRecording: Bool {
        if case .recording = appModel.sessionState {
            return true
        }
        return false
    }
    var statusColor: Color {
        switch appModel.sessionState {
        case .recording:
            return .red
        case .processing(.trimming):
            return .orange
        case .processing(.speeding):
            return .teal
        case .processing(.transcribing), .processing(.refining), .idle, .error:
            return .primary
        }
    }

    var statusErrorMessage: String? {
        guard case let .error(message) = appModel.sessionState else { return nil }
        return message
    }

    var transientMessage: String? {
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

                let title = String(normalizedTranscript.prefix(56))
                let subtitle = "\(entry.modeSummary.capitalized) • \(entry.preferredCharacterCount) chars"

                return HistoryMenuItem(
                    id: entry.id,
                    title: title,
                    subtitle: subtitle
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

    func droppedAudioFileRejected(_ error: AudioFileDropValidationError) {
        appModel.droppedAudioFileRejected(error)
    }

    func transcribeDroppedAudioFile(_ url: URL) async {
        await appModel.transcribeDroppedAudioFile(url)
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
