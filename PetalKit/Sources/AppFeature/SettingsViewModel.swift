import AudioClient
import CloudCleanupFeature
import Dependencies
import Foundation
import FoundationModelClient
import HistoryClient
import KeyboardShortcuts
import LogClient
import ModelDownloadFeature
import Observation
import PasteClient
import PermissionsClient
import RouterFeature
import Shared

@MainActor
@Observable
public final class SettingsViewModel {
    public enum DownloadState: Equatable {
        case ready
        case needsDownload
        case deleting
        case preparing
        case downloading(ModelDownloadState.Progress)
        case paused(ModelDownloadState.Progress)
        case failed(String)
    }

    @ObservationIgnored @Shared(.trimSilenceEnabled) public var trimSilenceEnabled
    @ObservationIgnored @Shared(.autoSpeedEnabled) public var autoSpeedEnabled
    @ObservationIgnored @Shared(.floatingCapsuleBackgroundStyle) public var floatingCapsuleBackgroundStyle: FloatingCapsuleBackgroundStyle
    @ObservationIgnored @Shared(.compressHistoryAudio) public var compressHistoryAudio
    @ObservationIgnored @Shared(.cleanupMinimumWords) public var cleanupMinimumWords: CleanupMinimumWords
    @ObservationIgnored @Shared(.cleanupModel) public var cleanupModel: CleanupModel
    @ObservationIgnored @Shared(.logsEnabled) public var logsEnabled
    @ObservationIgnored @Shared(.fileTranscriptionModelID) private var fileTranscriptionModelID
    @ObservationIgnored @Shared(.spokenLanguageCode) private var spokenLanguageCode
    @ObservationIgnored @Shared(.restoreClipboardAfterPaste) public var restoreClipboardAfterPaste
    @ObservationIgnored @Shared(.showLiveTranscript) public var showLiveTranscript
    @ObservationIgnored @Shared(.duckSystemAudioDuringRecording) public var duckSystemAudioDuringRecording
    @ObservationIgnored @Shared(.pushToTalkThreshold) public var pushToTalkThreshold: PushToTalkThreshold
    @ObservationIgnored @SharedReader(.shortcutTriggerMode) private var shortcutTriggerMode: ShortcutTriggerMode
    @ObservationIgnored @Shared(.selectedAudioInputDeviceID) private var selectedAudioInputDeviceID
    public var microphoneAuthorized: Bool { appModel.microphoneAuthorized }
    public var accessibilityAuthorized: Bool { appModel.accessibilityAuthorized }
    public private(set) var permissionMessage: String?
    private var launchAtLoginState: LaunchAtLoginState = .disabled
    public private(set) var launchAtLoginMessage: String?
    public var launchAtLoginEnabled: Bool { launchAtLoginState != .disabled }
    public private(set) var audioInputDevices: [AudioInputDevice] = [.systemDefault]

    public private(set) var selectedModelID: String {
        get { downloadModel.selectedModelID }
        set {
            appModel.selectedModelID = newValue
        }
    }

    public var selectedAudioInput: AudioInputDevice {
        get { audioInputDevices.first { $0.id == selectedAudioInputDeviceID } ?? .systemDefault }
        set {
            $selectedAudioInputDeviceID.withLock { $0 = newValue.id }
            appModel.prepareAudioCapture()
        }
    }

    public var isWarmingModel: Bool {
        appModel.isWarmingModel
    }

    public var logFileURL: URL? { logClient.logFileURL() }

    public var shortcut: RecordedShortcut {
        get {
            access(keyPath: \.shortcut)
            return recordingShortcut.current()
        }
        set {
            withMutation(keyPath: \.shortcut) { recordingShortcut.record(newValue) }
            if case .combo = newValue { recordingShortcut.resolvePasteConflict() }
            appModel.registerShortcutHandlers()
        }
    }

    public var shortcutDescription: String {
        switch shortcutTriggerMode {
        case .combo:
            "Tap to toggle recording, or hold and release to stop."
        case .doubleTap:
            "Press the same key twice quickly to activate. Hold the second press for push-to-talk."
        }
    }

    public var appleIntelligenceAvailable: Bool {
        foundationModelClient.isAvailable()
    }

    public var routerNotice: RouterNotice? {
        switch cleanupModel {
        case .off: return router.routeCleanupModels.isEmpty ? .cleanupOff : nil
        case .petalW1: return .petalW1
        case .appleIntelligence, .cloud: return nil
        }
    }

    public var showsCloudCleanupSetup: Bool {
        cleanupModel == .cloud || router.routeCleanupModels.contains(.cloud)
    }

    public var unreadyRouteCleanupModel: CleanupModel? {
        guard let model = router.selectedCleanupModel, !appModel.isCleanupModelReady(model) else { return nil }
        return model
    }

    public var readyCleanupModels: Set<CleanupModel> {
        Set(CleanupModel.allCases.filter(appModel.isCleanupModelReady))
    }

    public func historyCleanupModel(for entry: TranscriptHistoryEntry) -> CleanupModel {
        router.routes.route(for: entry.app)?.cleanupModel ?? cleanupModel
    }

    public var cloudCleanupDetail: String? {
        guard cloudCleanup.isConfigured else { return nil }
        return cloudCleanup.selectedModel.title
    }

    public var visibleModelOptions: [ModelOption] {
        let options = ModelOption.allCases
        var seen: Set<ModelProvider> = []
        let providers = options.map(\.provider).filter { seen.insert($0).inserted }
        return providers.flatMap { provider in options.filter { $0.provider == provider } }
    }

    public let downloadModel: ModelDownloadModel
    public let cleanupDownload: LocalCleanupDownloadModel
    public let history: HistoryLibraryModel
    public private(set) var reprocessingHistoryEntryID: UUID?
    public let cloudCleanup: CloudCleanupModel
    public let router: RouterModel
    private let appModel: AppModel
    @ObservationIgnored @Dependency(\.permissionsClient) private var permissionsClient
    @ObservationIgnored @Dependency(\.audioClient) private var audioClient
    @ObservationIgnored @Dependency(\.recordingShortcut) private var recordingShortcut
    @ObservationIgnored @Dependency(\.pasteClient) private var pasteClient
    @ObservationIgnored @Dependency(\.foundationModelClient) private var foundationModelClient
    @ObservationIgnored @Dependency(\.logClient) private var logClient

    public init(appModel: AppModel) {
        downloadModel = appModel.modelDownloadViewModel
        cleanupDownload = appModel.cleanupDownload
        history = withDependencies(from: appModel) { HistoryLibraryModel() }
        cloudCleanup = appModel.cloudCleanup
        router = appModel.router
        self.appModel = appModel
    }

    public func cleanupModelTapped(_ model: CleanupModel) async {
        $cleanupModel.withLock { $0 = model }
        appModel.cleanupModelDidChange()
        // Speech and cleanup model downloads share one aria2 session.
        if model.isLocal, canStartDownload {
            await cleanupDownload.downloadButtonTapped()
        }
    }

    public func refreshPermissions() async {
        await appModel.refreshPermissionStatusAsync()
        launchAtLoginState = await permissionsClient.launchAtLoginState()
    }

    public func launchAtLoginToggled(_ enabled: Bool) async {
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

    public func refreshAudioInputDevices() async {
        let devices = await audioClient.availableInputDevices()
        guard !devices.isEmpty else { return }
        audioInputDevices = devices

        if !devices.contains(where: { $0.id == selectedAudioInputDeviceID }) {
            selectedAudioInput = .systemDefault
        }
    }

    public func reprocessHistoryEntry(_ entry: TranscriptHistoryEntry, cleansUp: Bool) async {
        guard appModel.historyClient.historyAudioURL(entry.audioRelativePath) != nil else {
            permissionMessage = "The original recording is no longer available."
            return
        }
        guard reprocessingHistoryEntryID == nil else { return }
        reprocessingHistoryEntryID = entry.id
        defer { reprocessingHistoryEntryID = nil }
        await appModel.reprocessTranscriptHistoryButtonTapped(entry.id, cleansUp: cleansUp)
    }

    public func grantMicrophonePermissionButtonTapped() async {
        let granted = await permissionsClient.requestMicrophonePermission()
        await appModel.refreshPermissionStatusAsync()
        if !granted {
            permissionMessage = "Open System Settings to grant microphone access."
            await permissionsClient.openMicrophonePrivacySettings()
        }
    }

    public func grantAccessibilityPermissionButtonTapped() async {
        await permissionsClient.promptForAccessibilityPermission()
        await appModel.refreshPermissionStatusAsync()
        if !accessibilityAuthorized {
            permissionMessage = "Open System Settings to grant accessibility access."
        }
    }

    private var canStartDownload: Bool {
        !downloadModel.state.isActive && !downloadModel.state.isPaused && !cleanupDownload.state.isActive
    }

    public func modelOptionTapped(_ option: ModelOption) async {
        guard !downloadModel.isDeletingModel(option), selectedModelID != option.rawValue else { return }
        if downloadModel.isModelDownloaded(option) {
            selectedModelID = option.rawValue
        } else {
            ensureReadySelectedModel(excluding: option)
            guard canStartDownload else { return }
            await downloadModel.downloadModel(option)
        }
    }

    public func downloadState(for option: ModelOption) -> DownloadState {
        guard option.requiresDownload else { return .ready }
        guard !downloadModel.isDeletingModel(option) else { return .deleting }

        let state = downloadModel.state
        if downloadModel.downloadingModelOption == option {
            switch state {
            case .downloaded: return .ready
            case .notDownloaded: break
            case .preparing: return .preparing
            case let .downloading(progress): return .downloading(progress)
            case let .paused(progress): return .paused(progress)
            case let .failed(message): return .failed(message)
            }
        }

        return downloadModel.isModelDownloaded(option) ? .ready : .needsDownload
    }

    public var fileTranscriptionModel: ModelOption? {
        appModel.fileTranscriptionModelOverride
    }

    public var downloadedModelOptions: [ModelOption] {
        ModelOption.allCases.filter { downloadModel.isModelDownloaded($0) }
    }

    public var spokenLanguage: SpokenLanguage? {
        SpokenLanguage(rawValue: spokenLanguageCode)
    }

    public var offersSpokenLanguageChoice: Bool {
        downloadedModelOptions.contains(where: \.supportsSpokenLanguageChoice)
    }

    public func spokenLanguagePicked(_ language: SpokenLanguage?) {
        $spokenLanguageCode.withLock { $0 = language?.rawValue ?? "" }
    }

    public func dictationModelPicked(_ option: ModelOption) {
        guard downloadModel.isModelDownloaded(option) else { return }
        selectedModelID = option.rawValue
    }

    public func fileTranscriptionModelPicked(_ option: ModelOption?) {
        $fileTranscriptionModelID.withLock { $0 = option?.rawValue ?? "" }
    }

    public func deleteDownloadedModel(_ option: ModelOption) async {
        if selectedModelID == option.rawValue {
            ensureReadySelectedModel(excluding: option)
        }

        await downloadModel.deleteModel(option)
        if fileTranscriptionModelID == option.rawValue {
            $fileTranscriptionModelID.withLock { $0 = "" }
        }
        appModel.refreshModelCatalog()

        if selectedModelID == option.rawValue {
            ensureReadySelectedModel(excluding: option)
        }
    }

    private func ensureReadySelectedModel(excluding excludedOption: ModelOption) {
        if let selectedOption = ModelOption(rawValue: selectedModelID),
           selectedOption != excludedOption,
           downloadModel.isModelDownloaded(selectedOption)
        {
            return
        }

        let alternatives = ModelOption.allCases.filter { $0 != excludedOption }
        if let fallback = alternatives.first(where: downloadModel.isModelDownloaded) ?? alternatives.first {
            selectedModelID = fallback.rawValue
        }
    }

    public func copyButtonTapped(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        pasteClient.copy(text)
    }

    public func deleteHistoryEntry(_ entry: TranscriptHistoryEntry) {
        appModel.deleteTranscriptHistoryButtonTapped(entry.id)
    }

    public func pasteLastTranscriptionShortcutRecorded() {
        recordingShortcut.resolvePasteConflict()
    }
}
