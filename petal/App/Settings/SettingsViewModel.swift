import AppKit
import AudioClient
import CloudCleanupFeature
import Combine
import Dependencies
import FoundationModelClient
import HistoryClient
import KeyboardShortcuts
import LogClient
import ModelDownloadFeature
import Observation
import PermissionsClient
import RouterFeature
import Shared
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class SettingsViewModel {
    @ObservationIgnored @Shared(.trimSilenceEnabled) var trimSilenceEnabled = false
    @ObservationIgnored @Shared(.autoSpeedEnabled) var autoSpeedEnabled = false
    @ObservationIgnored @Shared(.transcriptionMode) var transcriptionMode: TranscriptionMode = .verbatim
    @ObservationIgnored @Shared(.smartPrompt) var smartPrompt = TranscriptionMode.defaultSmartPrompt
    @ObservationIgnored @Shared(.historyRetentionMode) var historyRetentionMode: HistoryRetentionMode = .both
    @ObservationIgnored @Shared(.floatingCapsuleBackgroundStyle) var floatingCapsuleBackgroundStyle: FloatingCapsuleBackgroundStyle = .liquidGlass
    @ObservationIgnored @Shared(.compressHistoryAudio) var compressHistoryAudio = true
    @ObservationIgnored @Shared(.cleanupMinimumWords) var cleanupMinimumWords: CleanupMinimumWords = .three
    @ObservationIgnored @Shared(.cleanupModel) var cleanupModel: CleanupModel = .off
    @ObservationIgnored @Shared(.logsEnabled) var logsEnabled = false
    @ObservationIgnored @Shared(.restoreClipboardAfterPaste) var restoreClipboardAfterPaste = true
    @ObservationIgnored @Shared(.showLiveTranscript) var showLiveTranscript = true
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
    var launchAtLoginState: LaunchAtLoginState = .disabled
    var launchAtLoginMessage: String?
    var launchAtLoginEnabled: Bool { launchAtLoginState != .disabled }
    var audioInputDevices: [AudioInputDevice] = [
        AudioInputDevice(id: AudioInputDevice.systemDefaultID, name: "System Default", isSystemDefault: true),
    ]
    private(set) var loadedHistory: [UUID: LoadedHistoryEntry] = [:]
    /// `false` until the newest recordings load, so History does not flash its empty state.
    private(set) var hasLoadedHistory = false
    private(set) var reprocessingHistoryEntryID: UUID?
    @ObservationIgnored private var staleHistoryEntryIDs: Set<UUID> = []
    private static let firstHistoryPageSize = 24

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

    var historyDirectoryDisplayPath: String {
        historyDirectoryPath.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~"
        )
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

    var smartModeAvailable: Bool {
        downloadModel.selectedModelOption?.supportsSmartTranscription == true
    }

    var usesSmartTranscription: Bool {
        smartModeAvailable && transcriptionMode == .smart
    }

    var routerNotice: RouterNotice? {
        if usesSmartTranscription { return .smartTranscription }
        switch cleanupModel {
        case .off: return .cleanupOff
        case .petalW1: return .petalW1
        case .appleIntelligence, .cloud: return nil
        }
    }

    var canCleanUpHistory: Bool {
        appModel.readyCleanupModel != nil
    }

    var cloudCleanupDetail: String? {
        guard cloudCleanup.isConfigured else { return nil }
        return cloudCleanup.selectedModel.title
    }

    var modelProviderGroups: IdentifiedArrayOf<ModelOptionProviderGroup> {
        ModelOption.providerGroups()
    }

    let downloadModel: ModelDownloadModel
    let cleanupDownloads: LocalCleanupDownloads
    let cloudCleanup: CloudCleanupModel
    let router: RouterModel
    private let appModel: AppModel
    @ObservationIgnored @Dependency(\.permissionsClient) private var permissionsClient
    @ObservationIgnored @Dependency(\.audioClient) private var audioClient
    @ObservationIgnored @Dependency(\.historyClient) private var historyClient
    @ObservationIgnored @Dependency(\.foundationModelClient) private var foundationModelClient
    @ObservationIgnored @Dependency(\.logClient) private var logClient

    init(appModel: AppModel) {
        downloadModel = appModel.modelDownloadViewModel
        cleanupDownloads = appModel.cleanupDownloads
        cloudCleanup = appModel.cloudCleanup
        router = appModel.router
        self.appModel = appModel
    }

    func cleanupModelTapped(_ model: CleanupModel) async {
        $cleanupModel.withLock { $0 = model }
        appModel.cleanupModelDidChange()
        // Speech and cleanup model downloads share one aria2 session.
        if let download = cleanupDownloads[model], !downloadModel.state.isActive, !downloadModel.state.isPaused, !cleanupDownloads.isAnyActive {
            await download.downloadButtonTapped()
        }
    }

    func refreshPermissions() async {
        microphoneAuthorized = await permissionsClient.microphonePermissionState() == .authorized
        accessibilityAuthorized = await permissionsClient.hasAccessibilityPermission()
        launchAtLoginState = await permissionsClient.launchAtLoginState()
    }

    func launchAtLoginToggled(_ enabled: Bool) async {
        launchAtLoginMessage = nil
        do {
            launchAtLoginState = try await permissionsClient.setLaunchAtLogin(enabled)
            if launchAtLoginState == .requiresApproval {
                launchAtLoginMessage = "Allow Petal in System Settings > General > Login Items."
                await permissionsClient.openLoginItemsSettings()
            }
        } catch {
            launchAtLoginState = await permissionsClient.launchAtLoginState()
            launchAtLoginMessage = "Petal could not change the login item. Move Petal to the Applications folder and try again."
            logClient.error("Settings", "Launch at login change failed: \(error.localizedDescription)")
        }
    }

    func refreshAudioInputDevices() async {
        let devices = await audioClient.availableInputDevices()
        guard !devices.isEmpty else { return }
        audioInputDevices = devices

        if !devices.contains(where: { $0.id == selectedAudioInputID }) {
            selectedAudioInputID = AudioInputDevice.systemDefaultID
        }
    }

    /// Reads History's files away from the main actor, newest first, and again whenever history changes.
    func historyTask() async {
        // `Observations` needs macOS 26, so this follows the shared value through its publisher.
        for await _ in $transcriptHistoryDays.publisher.values {
            await loadHistory()
        }
    }

    /// Entries show once their files load, so a card never renders without its text.
    func historyDays(matching query: String) -> [TranscriptHistoryDay] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isShown = { (entry: TranscriptHistoryEntry) -> Bool in
            guard let loaded = self.loadedHistory[entry.id] else { return false }
            return search.isEmpty || loaded.searchText.contains(search)
        }
        return historyDays.compactMap { day in
            guard !day.entries.allSatisfy(isShown) else { return day }
            var filteredDay = day
            filteredDay.entries.removeAll { !isShown($0) }
            return filteredDay.entries.isEmpty ? nil : filteredDay
        }
    }

    func historyAudioURL(for entry: TranscriptHistoryEntry) -> URL? {
        loadedHistory[entry.id]?.audioURL
    }

    func historyEntryFailed(_ entry: TranscriptHistoryEntry) -> Bool {
        entry.variants[id: "failed"] != nil && entry.variants.count == 1
    }

    func reprocessHistoryEntry(_ entry: TranscriptHistoryEntry, cleansUp: Bool) async {
        guard historyClient.historyAudioURL(entry.audioRelativePath) != nil else {
            permissionMessage = "The original recording is no longer available."
            return
        }

        reprocessingHistoryEntryID = entry.id
        defer { reprocessingHistoryEntryID = nil }
        await appModel.reprocessTranscriptHistoryButtonTapped(entry.id, cleansUp: cleansUp)
        // The new transcript can reuse the old file name, so an unchanged entry still reads its files again.
        staleHistoryEntryIDs.insert(entry.id)
        await loadHistory()
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
        guard !downloadModel.state.isActive, !downloadModel.state.isPaused, !cleanupDownloads.isAnyActive else { return }
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
        appModel.refreshModelCatalog()

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

    func copyButtonTapped(_ text: String) {
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func historyText(for entry: TranscriptHistoryEntry) -> HistoryEntryText {
        loadedHistory[entry.id]?.text ?? HistoryEntryText()
    }

    func deleteHistoryEntry(_ entry: TranscriptHistoryEntry) {
        appModel.deleteTranscriptHistoryButtonTapped(entry.id)
        loadedHistory[entry.id] = nil
    }

    private func loadHistory() async {
        while !Task.isCancelled {
            var entryIDs = Set<UUID>()
            var stale: [(day: String, entry: TranscriptHistoryEntry)] = []
            for day in historyDays {
                for entry in day.entries {
                    entryIDs.insert(entry.id)
                    if loadedHistory[entry.id]?.entry != entry || staleHistoryEntryIDs.contains(entry.id) {
                        stale.append((day.day, entry))
                    }
                }
            }
            if loadedHistory.keys.contains(where: { !entryIDs.contains($0) }) {
                loadedHistory = loadedHistory.filter { entryIDs.contains($0.key) }
            }
            guard !stale.isEmpty else { break }

            // The newest recordings fill the first screen, so they load before the rest.
            let batch = hasLoadedHistory ? stale : Array(stale.prefix(Self.firstHistoryPageSize))
            let loaded = await Self.loadHistoryEntries(batch, historyClient: historyClient)
            guard !Task.isCancelled else { return }
            loadedHistory.merge(loaded) { $1 }
            staleHistoryEntryIDs.subtract(loaded.keys)
            hasLoadedHistory = true
        }
        if !Task.isCancelled {
            hasLoadedHistory = true
        }
    }

    @concurrent
    nonisolated private static func loadHistoryEntries(
        _ requests: [(day: String, entry: TranscriptHistoryEntry)],
        historyClient: HistoryClient
    ) async -> [UUID: LoadedHistoryEntry] {
        let contents = await historyClient.entryContents(requests.map { $0.entry })
        var loaded: [UUID: LoadedHistoryEntry] = [:]
        loaded.reserveCapacity(requests.count)
        for request in requests {
            loaded[request.entry.id] = LoadedHistoryEntry(
                day: request.day,
                entry: request.entry,
                contents: contents[request.entry.id] ?? HistoryEntryContents()
            )
        }
        return loaded
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
