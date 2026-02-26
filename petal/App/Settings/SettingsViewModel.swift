import AppKit
import UniformTypeIdentifiers
import Dependencies
import FoundationModelClient
import HistoryClient
import LogClient
import ModelDownloadFeature
import Observation
import PermissionsClient
import Shared

@MainActor
@Observable
final class SettingsViewModel {
    @ObservationIgnored @Shared(.trimSilenceEnabled) var trimSilenceEnabled = false
    @ObservationIgnored @Shared(.autoSpeedEnabled) var autoSpeedEnabled = false
    @ObservationIgnored @Shared(.transcriptionMode) var transcriptionMode: TranscriptionMode = .verbatim
    @ObservationIgnored @Shared(.smartPrompt) var smartPrompt = "Clean up filler words and repeated phrases. Return a polished version of what was said."
    @ObservationIgnored @Shared(.historyRetentionMode) var historyRetentionMode: HistoryRetentionMode = .both
    @ObservationIgnored @Shared(.compressHistoryAudio) var compressHistoryAudio = false
    @ObservationIgnored @Shared(.appleIntelligenceEnabled) var appleIntelligenceEnabled = false
    @ObservationIgnored @Shared(.logsEnabled) var logsEnabled = false
    @ObservationIgnored @Shared(.restoreClipboardAfterPaste) var restoreClipboardAfterPaste = true
    @ObservationIgnored @Shared(.pushToTalkThreshold) var pushToTalkThreshold: PushToTalkThreshold = .long
    @ObservationIgnored @Shared(.doubleTapModifierEnabled) var doubleTapModifierEnabled = false
    @ObservationIgnored @Shared(.doubleTapModifierKey) var doubleTapModifierKey: DoubleTapModifierKey = .fn
    @ObservationIgnored @Shared(.transcriptHistoryDays) private var transcriptHistoryDays: [TranscriptHistoryDay] = []

    var microphoneAuthorized = false
    var accessibilityAuthorized = false
    var permissionMessage: String?

    var selectedModelID: String {
        get { downloadModel.selectedModelID }
        set {
            appModel.selectedModelID = newValue
        }
    }

    var isWarmingModel: Bool { appModel.isWarmingModel }

    var historyDirectoryPath: String {
        historyClient.historyDirectoryPath()
    }

    var recentHistoryEntries: [TranscriptHistoryEntry] {
        transcriptHistoryDays.flatMap(\.entries)
            .filter { transcriptText(for: $0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(3)
            .map { $0 }
    }

    var canExportLogs: Bool {
        logClient.logFileURL() != nil
    }

    var appleIntelligenceAvailable: Bool {
        foundationModelClient.isAvailable()
    }

    /// Whether smart mode should be available for the currently selected model.
    var smartModeAvailable: Bool {
        downloadModel.selectedModelOption?.supportsSmartTranscription == true
            || appleIntelligenceEnabled
    }

    let downloadModel: ModelDownloadModel
    private let appModel: AppModel
    @ObservationIgnored @Dependency(\.permissionsClient) private var permissionsClient
    @ObservationIgnored @Dependency(\.historyClient) private var historyClient
    @ObservationIgnored @Dependency(\.foundationModelClient) private var foundationModelClient
    @ObservationIgnored @Dependency(\.logClient) private var logClient

    init(appModel: AppModel) {
        self.downloadModel = appModel.modelDownloadViewModel
        self.appModel = appModel
    }

    func refreshPermissions() async {
        microphoneAuthorized = await permissionsClient.microphonePermissionState() == .authorized
        accessibilityAuthorized = await permissionsClient.hasAccessibilityPermission()
    }

    func grantMicrophonePermissionButtonTapped() async {
        let granted = await permissionsClient.requestMicrophonePermission()
        microphoneAuthorized = granted
        if !granted {
            permissionMessage = "Open System Settings to grant microphone access."
            await permissionsClient.openMicrophonePrivacySettings()
        }
    }

    func grantAccessibilityPermissionButtonTapped() async {
        await permissionsClient.promptForAccessibilityPermission()
        try? await Task.sleep(for: .milliseconds(500))
        accessibilityAuthorized = await permissionsClient.hasAccessibilityPermission()
        if !accessibilityAuthorized {
            permissionMessage = "Open System Settings to grant accessibility access."
        }
    }

    func downloadButtonTapped() async {
        await downloadModel.downloadButtonTapped()
    }

    func pauseButtonTapped() {
        downloadModel.pauseButtonTapped()
    }

    func resumeButtonTapped() async {
        await downloadModel.resumeButtonTapped()
    }

    func cancelButtonTapped() {
        downloadModel.cancelButtonTapped()
    }

    func deleteModelButtonTapped() async {
        await downloadModel.deleteModelButtonTapped()
    }

    func historyRetentionModeChanged(_ mode: HistoryRetentionMode) {
        $historyRetentionMode.withLock { $0 = mode }
        let applied = historyClient.applyRetention(mode, transcriptHistoryDays)
        $transcriptHistoryDays.withLock { $0 = applied }
    }

    func doubleTapModifierEnabledChanged(_ enabled: Bool) {
        $doubleTapModifierEnabled.withLock { $0 = enabled }
        appModel.registerDoubleTapMonitor()
    }

    func doubleTapModifierKeyChanged(_ key: DoubleTapModifierKey) {
        $doubleTapModifierKey.withLock { $0 = key }
        appModel.registerDoubleTapMonitor()
    }

    func openHistoryInFinder() {
        _ = historyClient.openHistoryFolder(historyRetentionMode)
    }

    func copyHistoryEntry(_ entry: TranscriptHistoryEntry) {
        let transcript = transcriptText(for: entry)
        guard transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
    }

    func transcriptText(for entry: TranscriptHistoryEntry) -> String {
        historyClient.transcriptText(entry.preferredTranscriptRelativePath) ?? ""
    }

    func deleteAllHistory() {
        let cleared = historyClient.applyRetention(.none, transcriptHistoryDays)
        $transcriptHistoryDays.withLock { $0 = cleared }
    }

    func deleteMediaOnly() {
        let updated = historyClient.deleteMediaOnly(transcriptHistoryDays)
        $transcriptHistoryDays.withLock { $0 = updated }
    }

    func exportLogs() {
        guard let logURL = logClient.logFileURL() else { return }
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = logURL.lastPathComponent
        savePanel.allowedContentTypes = [.plainText]
        guard savePanel.runModal() == .OK, let destination = savePanel.url else { return }
        try? FileManager.default.copyItem(at: logURL, to: destination)
    }
}
