import AppKit
import UniformTypeIdentifiers
import Dependencies
import FoundationModelClient
import HistoryClient
import KeyboardShortcuts
import LogClient
import ModelDownloadFeature
import Observation
import PermissionsClient
import Shared
import SwiftUI

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
    @ObservationIgnored @Shared(.duckSystemAudioDuringRecording) var duckSystemAudioDuringRecording = false
    @ObservationIgnored @Shared(.pushToTalkThreshold) var pushToTalkThreshold: PushToTalkThreshold = .long
    @ObservationIgnored @Shared(.shortcutTriggerMode) var shortcutTriggerMode: ShortcutTriggerMode = .combo
    @ObservationIgnored @Shared(.doubleTapKey) var doubleTapKey: DoubleTapKey = .unconfigured
    @ObservationIgnored @Shared(.doubleTapInterval) var doubleTapInterval: Double = 0.4
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

    var unifiedShortcutBinding: Binding<RecordedShortcut> {
        Binding(
            get: { [weak self] in
                guard let self else { return .unconfigured }
                switch self.shortcutTriggerMode {
                case .combo:
                    guard let shortcut = KeyboardShortcuts.getShortcut(for: .pushToTalk) else {
                        return .unconfigured
                    }
                    var displayNames = [String]()
                    let mods = shortcut.modifiers
                    if mods.contains(.control) { displayNames.append("\u{2303}") }
                    if mods.contains(.option) { displayNames.append("\u{2325}") }
                    if mods.contains(.command) { displayNames.append("\u{2318}") }
                    let keyChar = shortcut.keyToCharacter()?.capitalized ?? "Key \(shortcut.carbonKeyCode)"
                    displayNames.append(keyChar)
                    return .combo(
                        keyCode: shortcut.carbonKeyCode,
                        carbonModifiers: shortcut.carbonModifiers,
                        displayNames: displayNames
                    )
                case .doubleTap:
                    guard self.doubleTapKey.isConfigured else { return .unconfigured }
                    return .singleKey(
                        keyCode: self.doubleTapKey.keyCode,
                        isModifier: self.doubleTapKey.isModifier,
                        displayName: self.doubleTapKey.displayName
                    )
                }
            },
            set: { [weak self] newValue in
                self?.shortcutRecorded(newValue)
            }
        )
    }

    var shortcutDescription: String {
        switch shortcutTriggerMode {
        case .combo:
            "Tap to toggle recording, or hold and release to stop."
        case .doubleTap:
            "Press the same key twice quickly to activate. Hold the second press for push-to-talk."
        }
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

    func shortcutRecorded(_ result: RecordedShortcut) {
        switch result {
        case .unconfigured:
            KeyboardShortcuts.setShortcut(nil, for: .pushToTalk)
            $doubleTapKey.withLock { $0 = .unconfigured }

        case let .singleKey(keyCode, isModifier, _):
            $shortcutTriggerMode.withLock { $0 = .doubleTap }
            $doubleTapKey.withLock { $0 = DoubleTapKey(keyCode: keyCode, isModifier: isModifier) }
            $doubleTapInterval.withLock { $0 = 0.4 }
            KeyboardShortcuts.setShortcut(nil, for: .pushToTalk)

        case let .combo(keyCode, carbonModifiers, _):
            $shortcutTriggerMode.withLock { $0 = .combo }
            KeyboardShortcuts.setShortcut(
                .init(carbonKeyCode: keyCode, carbonModifiers: carbonModifiers),
                for: .pushToTalk
            )
            $doubleTapKey.withLock { $0 = .unconfigured }
        }
        appModel.registerShortcutHandlers()
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
