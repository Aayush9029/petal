import AppKit
import AudioClient
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
import UniformTypeIdentifiers

@MainActor
@Observable
final class SettingsViewModel {
    @ObservationIgnored @Shared(.trimSilenceEnabled) var trimSilenceEnabled = false
    @ObservationIgnored @Shared(.autoSpeedEnabled) var autoSpeedEnabled = false
    @ObservationIgnored @Shared(.transcriptionMode) var transcriptionMode: TranscriptionMode = .verbatim
    @ObservationIgnored @Shared(.smartPrompt) var smartPrompt = "Clean up filler words and repeated phrases. Return a polished version of what was said."
    @ObservationIgnored @Shared(.historyRetentionMode) var historyRetentionMode: HistoryRetentionMode = .both
    @ObservationIgnored @Shared(.floatingCapsuleBackgroundStyle) var floatingCapsuleBackgroundStyle: FloatingCapsuleBackgroundStyle = .liquidGlass
    @ObservationIgnored @Shared(.compressHistoryAudio) var compressHistoryAudio = true
    @ObservationIgnored @Shared(.appleIntelligenceEnabled) var appleIntelligenceEnabled = false
    @ObservationIgnored @Shared(.logsEnabled) var logsEnabled = false
    @ObservationIgnored @Shared(.restoreClipboardAfterPaste) var restoreClipboardAfterPaste = true
    @ObservationIgnored @Shared(.duckSystemAudioDuringRecording) var duckSystemAudioDuringRecording = false
    @ObservationIgnored @Shared(.pushToTalkThreshold) var pushToTalkThreshold: PushToTalkThreshold = .long
    @ObservationIgnored @Shared(.shortcutTriggerMode) var shortcutTriggerMode: ShortcutTriggerMode = .combo
    @ObservationIgnored @Shared(.doubleTapKey) var doubleTapKey: DoubleTapKey = .unconfigured
    @ObservationIgnored @Shared(.doubleTapInterval) var doubleTapInterval: Double = 0.4
    @ObservationIgnored @Shared(.selectedAudioInputDeviceID) var selectedAudioInputDeviceID = AudioInputDevice.systemDefaultID
    @ObservationIgnored @Shared(.transcriptHistoryDays) private var transcriptHistoryDays: [TranscriptHistoryDay] = []

    var microphoneAuthorized = false
    var accessibilityAuthorized = false
    var permissionMessage: String?
    var audioInputDevices: [AudioInputDevice] = [
        AudioInputDevice(id: AudioInputDevice.systemDefaultID, name: "System Default", isSystemDefault: true),
    ]
    private(set) var historyTranscriptCache: [UUID: String] = [:]
    private(set) var reprocessingHistoryEntryID: UUID?

    var selectedModelID: String {
        get { downloadModel.selectedModelID }
        set {
            appModel.selectedModelID = newValue
        }
    }

    var selectedAudioInputID: String {
        get { selectedAudioInputDeviceID }
        set {
            $selectedAudioInputDeviceID.withLock {
                $0 = newValue.isEmpty ? AudioInputDevice.systemDefaultID : newValue
            }
        }
    }

    var isWarmingModel: Bool {
        appModel.isWarmingModel
    }

    var historyDirectoryPath: String {
        historyClient.historyDirectoryPath()
    }

    var historyDays: [TranscriptHistoryDay] {
        transcriptHistoryDays.sorted { $0.day > $1.day }
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
                    if mods.contains(.control) {
                        displayNames.append("\u{2303}")
                    }
                    if mods.contains(.option) {
                        displayNames.append("\u{2325}")
                    }
                    if mods.contains(.command) {
                        displayNames.append("\u{2318}")
                    }
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

    var pinnedDownloadOption: ModelOption? {
        guard let option = downloadModel.downloadingModelOption else { return nil }

        switch downloadModel.state {
        case .preparing, .downloading, .paused, .failed:
            return option
        case .notDownloaded, .downloaded:
            return nil
        }
    }

    var modelProviderGroups: IdentifiedArrayOf<ModelOptionProviderGroup> {
        ModelOption.providerGroups(excluding: pinnedDownloadOption)
    }

    let downloadModel: ModelDownloadModel
    private let appModel: AppModel
    @ObservationIgnored @Dependency(\.permissionsClient) private var permissionsClient
    @ObservationIgnored @Dependency(\.audioClient) private var audioClient
    @ObservationIgnored @Dependency(\.historyClient) private var historyClient
    @ObservationIgnored @Dependency(\.foundationModelClient) private var foundationModelClient
    @ObservationIgnored @Dependency(\.logClient) private var logClient

    init(appModel: AppModel) {
        downloadModel = appModel.modelDownloadViewModel
        self.appModel = appModel
    }

    func refreshPermissions() async {
        microphoneAuthorized = await permissionsClient.microphonePermissionState() == .authorized
        accessibilityAuthorized = await permissionsClient.hasAccessibilityPermission()
    }

    func refreshAudioInputDevices() async {
        let devices = await audioClient.availableInputDevices()
        guard !devices.isEmpty else { return }
        audioInputDevices = devices

        if !devices.contains(where: { $0.id == selectedAudioInputID }) {
            selectedAudioInputID = AudioInputDevice.systemDefaultID
        }
    }

    func refreshHistory() {
        historyTranscriptCache = Dictionary(uniqueKeysWithValues: historyDays.flatMap { day in
            day.entries.map { entry in
                (entry.id, historyClient.transcriptText(entry.preferredTranscriptRelativePath) ?? "")
            }
        })
    }

    func historyDays(matching query: String) -> [TranscriptHistoryDay] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !search.isEmpty else { return historyDays }

        return historyDays.compactMap { day in
            var filteredDay = day
            filteredDay.entries.removeAll { entry in
                let transcript = historyTranscriptCache[entry.id, default: ""]
                let searchableText = [transcript, entry.modelID, entry.modeSummary, day.day]
                    .joined(separator: " ")
                    .lowercased()
                return !searchableText.contains(search)
            }
            return filteredDay.entries.isEmpty ? nil : filteredDay
        }
    }

    func historyAudioURL(for entry: TranscriptHistoryEntry) -> URL? {
        historyClient.historyAudioURL(entry.audioRelativePath)
    }

    func historyEntryFailed(_ entry: TranscriptHistoryEntry) -> Bool {
        entry.variants[id: "failed"] != nil && entry.variants.count == 1
    }

    func reprocessHistoryEntry(_ entry: TranscriptHistoryEntry) async {
        guard historyAudioURL(for: entry) != nil else {
            permissionMessage = "The original recording is no longer available."
            return
        }

        reprocessingHistoryEntryID = entry.id
        defer {
            reprocessingHistoryEntryID = nil
            refreshHistory()
        }
        await appModel.reprocessTranscriptHistoryButtonTapped(entry.id)
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

    func modelOptionTapped(_ option: ModelOption) -> ModelOption? {
        guard !downloadModel.isDeletingModel(option) else { return nil }
        guard selectedModelID != option.rawValue else { return nil }

        if option.requiresDownload, !downloadModel.isModelDownloaded(option) {
            ensureReadySelectedModel(excluding: option)
            guard !downloadModel.state.isActive, !downloadModel.state.isPaused else { return nil }
            return option
        }

        selectedModelID = option.rawValue
        return nil
    }

    func downloadModelConfirmed(_ option: ModelOption) async {
        guard !downloadModel.isDeletingModel(option) else { return }
        guard !downloadModel.state.isActive, !downloadModel.state.isPaused else { return }
        ensureReadySelectedModel(excluding: option)
        await downloadModel.downloadModel(option)
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

    func deleteDownloadedModel(_ option: ModelOption) async {
        if selectedModelID == option.rawValue {
            ensureReadySelectedModel(excluding: option)
        }

        await downloadModel.deleteModel(option)

        if selectedModelID == option.rawValue {
            ensureReadySelectedModel(excluding: option)
        }
    }

    private func ensureReadySelectedModel(excluding excludedOption: ModelOption) {
        if let selectedOption = ModelOption(rawValue: selectedModelID),
           selectedOption != excludedOption,
           !selectedOption.requiresDownload || downloadModel.isModelDownloaded(selectedOption)
        {
            return
        }

        if ModelOption.allCases.contains(.appleSpeech) {
            selectedModelID = ModelOption.appleSpeech.rawValue
            return
        }

        if let readyOption = ModelOption.allCases.first(where: {
            $0 != excludedOption && (!$0.requiresDownload || downloadModel.isModelDownloaded($0))
        }) {
            selectedModelID = readyOption.rawValue
            return
        }

        if let fallbackOption = ModelOption.allCases.first(where: { $0 != excludedOption }) {
            selectedModelID = fallbackOption.rawValue
        }
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
        historyTranscriptCache[entry.id]
            ?? historyClient.transcriptText(entry.preferredTranscriptRelativePath)
            ?? ""
    }

    func deleteAllHistory() {
        let cleared = historyClient.applyRetention(.none, transcriptHistoryDays)
        $transcriptHistoryDays.withLock { $0 = cleared }
        refreshHistory()
    }

    func deleteMediaOnly() {
        let updated = historyClient.deleteMediaOnly(transcriptHistoryDays)
        $transcriptHistoryDays.withLock { $0 = updated }
        refreshHistory()
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
