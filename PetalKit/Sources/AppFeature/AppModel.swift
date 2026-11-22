import AppKit
import AudioClient
import class SwiftUI.NSHostingView
import CloudCleanupClient
import CloudCleanupFeature
import DoubleTapClient
import FloatingCapsuleClient
import FoundationModelClient
import Foundation
import HistoryClient
import IssueReporting
import KeyboardClient
import KeyboardShortcuts
import LogClient
import Observation
import ModelDownloadFeature
import Onboarding
import PasteClient
import PermissionsClient
import PlaybackDuckingClient
import RouterFeature
import LocalCleanupClient
import Shared
import SoundClient
import SystemContextClient
import TranscriptionClient
import WindowClient

@MainActor
@Observable
public final class AppModel {
    typealias ProcessingStage = TranscriptionStage

    enum SessionState: Equatable {
        case idle
        case recording
        case processing(ProcessingStage)
        case error(String)
    }

    @ObservationIgnored @Shared(.hasCompletedSetup) var hasCompletedSetup
    @ObservationIgnored @Shared(.fileTranscriptionModelID) var fileTranscriptionModelID
    @ObservationIgnored @Shared(.transcriptionMode) var transcriptionMode: TranscriptionMode
    @ObservationIgnored @Shared(.smartPrompt) var smartPrompt
    @ObservationIgnored @Shared(.cleanupModel) var cleanupModel: CleanupModel
    @ObservationIgnored @Shared(.cleanupMinimumWords) var cleanupMinimumWords: CleanupMinimumWords
    @ObservationIgnored @Shared(.compressHistoryAudio) var compressHistoryAudio
    @ObservationIgnored @Shared(.historyRetentionMode) var historyRetentionMode: HistoryRetentionMode
    @ObservationIgnored @Shared(.pushToTalkThreshold) var pushToTalkThreshold: PushToTalkThreshold
    @ObservationIgnored @Shared(.restoreClipboardAfterPaste) var restoreClipboardAfterPaste
    @ObservationIgnored @Shared(.showLiveTranscript) var showLiveTranscript
    @ObservationIgnored @Shared(.duckSystemAudioDuringRecording) var duckSystemAudioDuringRecording
    @ObservationIgnored @Shared(.shortcutTriggerMode) var shortcutTriggerMode: ShortcutTriggerMode
    @ObservationIgnored @Shared(.doubleTapKey) var doubleTapKey: DoubleTapKey
    @ObservationIgnored @Shared(.doubleTapInterval) var doubleTapInterval: Double
    @ObservationIgnored @Shared(.transcriptHistoryDays) var transcriptHistoryDays: [TranscriptHistoryDay]
    @ObservationIgnored @Shared(.modelCatalog) var modelCatalog: IdentifiedArrayOf<ModelCatalogEntry>
    @ObservationIgnored @Shared(.cleanupRoutes) var cleanupRoutes: IdentifiedArrayOf<CleanupRoute>
    @ObservationIgnored @Shared(.cleanupFallbackAction) var cleanupFallbackAction: CleanupRoute.Action

    let modelDownloadViewModel: ModelDownloadModel
    let cleanupDownload = LocalCleanupDownloadModel()
    let cloudCleanup = CloudCleanupModel()
    let router: RouterModel

    var selectedModelID: String {
        get { modelDownloadViewModel.selectedModelID }
        set {
            modelDownloadViewModel.$selectedModelID.withLock { $0 = newValue }
            selectedModelDidChange()
        }
    }

    var sessionState: SessionState = .idle
    var currentLevel: Double = 0
    var menuTransientMessage: String?
    var isWarmingModel = false
    var microphonePermissionState: MicrophonePermissionState = .notDetermined
    var microphoneAuthorized: Bool { microphonePermissionState == .authorized }
    var accessibilityAuthorized = false

    var onboardingModel: OnboardingModel?

    @ObservationIgnored @Dependency(\.continuousClock) var clock
    @ObservationIgnored @Dependency(\.date.now) var now
    @ObservationIgnored @Dependency(\.uuid) var uuid
    @ObservationIgnored @Dependency(\.transcriptionClient) var transcriptionClient
    @ObservationIgnored @Dependency(\.notificationClient) var notificationClient
    @ObservationIgnored @Dependency(\.pasteClient) var pasteClient
    @ObservationIgnored @Dependency(\.permissionsClient) var permissionsClient
    @ObservationIgnored @Dependency(\.audioClient) var audioClient
    @ObservationIgnored @Dependency(\.keyboardClient) var keyboardClient
    @ObservationIgnored @Dependency(\.floatingCapsuleClient) var floatingCapsuleClient
    @ObservationIgnored @Dependency(\.soundClient) var soundClient
    @ObservationIgnored @Dependency(\.historyClient) var historyClient
    @ObservationIgnored @Dependency(\.logClient) var logClient
    @ObservationIgnored @Dependency(\.foundationModelClient) var foundationModelClient
    @ObservationIgnored @Dependency(\.localCleanupClient) var localCleanupClient
    @ObservationIgnored @Dependency(\.cloudCleanupClient) var cloudCleanupClient
    @ObservationIgnored @Dependency(\.doubleTapClient) var doubleTapClient
    @ObservationIgnored @Dependency(\.windowClient) var windowClient
    @ObservationIgnored @Dependency(\.playbackDuckingClient) var playbackDuckingClient
    @ObservationIgnored @Dependency(\.systemContextClient) var systemContextClient

    @ObservationIgnored let isPreviewMode: Bool

    @ObservationIgnored var didBootstrap = false
    @ObservationIgnored var recordingShortcut: RecordingShortcut = .idle
    @ObservationIgnored var recordingTransition: RecordingTransition?
    @ObservationIgnored var cancelConfirmationTimerTask: Task<Void, Never>?
    @ObservationIgnored var isTranscribingDroppedFile = false
    @ObservationIgnored var transcriptionProgressTask: Task<Void, Never>?
    @ObservationIgnored var accessibilityFollowUpTask: Task<Void, Never>?
    @ObservationIgnored var permissionMonitorTask: Task<Void, Never>?
    @ObservationIgnored var warmupTask: Task<Void, Never>?
    @ObservationIgnored var cleanupWarmupTask: Task<Void, Never>?
    @ObservationIgnored var pasteLastTranscriptionTask: Task<Void, Never>?
    @ObservationIgnored var isShowingMiniDownload = false
    @ObservationIgnored var recordingSession: RecordingSession?
    @ObservationIgnored var streamingTask: Task<String, any Error>?
    @ObservationIgnored var sendNowChordStart: Date?
    @ObservationIgnored var lastTranscript: String?
    @ObservationIgnored var estimatedTranscriptionRTF = 2.2
    nonisolated static let deepLinkStartTimeoutSeconds = 12.0

    nonisolated static var isRunningUnattendedE2E: Bool {
        if ProcessInfo.processInfo.environment["PETAL_UNATTENDED_E2E"] == "1" {
            return true
        }
        return UserDefaults.standard.bool(forKey: "unattended_e2e_mode")
    }

    private let showSettings: @MainActor (AppModel) -> Void

    public init(
        isPreviewMode: Bool = false,
        showSettings: @escaping @MainActor (AppModel) -> Void = unimplemented("AppModel.showSettings")
    ) {
        self.showSettings = showSettings
        self.isPreviewMode = isPreviewMode
        modelDownloadViewModel = ModelDownloadModel()
        router = RouterModel(cloud: cloudCleanup)

        if isPreviewMode {
            microphonePermissionState = .authorized
            accessibilityAuthorized = true
        }
    }

    var selectedModelOption: ModelOption? {
        modelDownloadViewModel.selectedModelOption
    }

    var fileTranscriptionModelOverride: ModelOption? {
        ModelOption.fileOverride(
            id: fileTranscriptionModelID, dictationModel: selectedModelOption,
            isReady: modelDownloadViewModel.isModelDownloaded
        )
    }

    var isSelectedModelDownloaded: Bool {
        modelDownloadViewModel.isSelectedModelDownloaded
    }

    var statusTitle: String {
        switch sessionState {
        case .idle:
            return hasCompletedSetup ? "Ready" : "Setup needed"
        case .recording:
            return "REC"
        case let .processing(stage):
            switch stage {
            case .trimming: return "Trimming"
            case .speeding: return "Speeding up"
            case .transcribing: return "Transcribing"
            case .refining: return "Refining"
            }
        case .error:
            return "Error"
        }
    }

    var menuBarIconState: MenuBarIconState {
        if modelDownloadViewModel.state.isActive || modelDownloadViewModel.state.isPaused {
            return .working
        }
        switch sessionState {
        case .idle: return .idle
        case .recording: return .recording
        case .processing: return .working
        case .error: return .error
        }
    }

    public var isIdle: Bool {
        sessionState == .idle && menuBarIconState == .idle
            && !isRecordingLifecycleBusy
    }

    var recentTranscriptHistoryEntries: [TranscriptHistoryEntry] {
        transcriptHistoryDays
            .flatMap(\.entries)
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(20)
            .map { $0 }
    }

    func selectedModelDidChange() {
        menuTransientMessage = nil
        modelDownloadViewModel.selectedModelChanged()
        prepareAudioCapture()
        estimatedTranscriptionRTF = defaultTranscriptionRTF(for: selectedModelOption)
        let normalizedMode = normalizedTranscriptionMode(transcriptionMode)
        if transcriptionMode != normalizedMode {
            $transcriptionMode.withLock { $0 = normalizedMode }
        }
        guard hasCompletedSetup, isSelectedModelDownloaded, !isRecordingLifecycleBusy, sessionState != .recording else { return }
        scheduleWarmup()
    }

    func scheduleWarmup() {
        guard let model = selectedModelOption else { return }
        warmupTask?.cancel()
        isWarmingModel = true
        warmupTask = Task {
            await transcriptionClient.unloadModel()
            await warmModelTask(model)
            if !Task.isCancelled { isWarmingModel = false }
        }
    }

    func changeModelButtonTapped() {
        if isPreviewMode { return }
        beginOnboardingFlow()
        showOnboardingWindow()
    }

    public func openSettingsWindow() {
        if isPreviewMode { return }
        showSettings(self)
    }

    public func appDidLaunch() async {
        if isPreviewMode { return }
        guard !didBootstrap else { return }
        didBootstrap = true
        modelDownloadViewModel.task()
        modelDownloadViewModel.onDownloadCompleted = { [weak self] option in
            guard let self else { return }
            refreshModelCatalog()
            guard option == selectedModelOption else { return }
            expandFromMiniDownload()
            if hasCompletedSetup, !isRecordingLifecycleBusy, sessionState != .recording { scheduleWarmup() }
        }
        registerShortcutHandlers()
        listenForPasteLastTranscriptionShortcut()
        registerKeyboardMonitor()
        startPermissionMonitoring()
        Task { await bootstrapHistory() }
        Task { await cleanupDownload.updateIfOutdated() }

        logClient.debug("AppModel", "App did launch. setupCompleted=\(self.hasCompletedSetup), modelDownloaded=\(self.isSelectedModelDownloaded)")

        Task { await soundClient.warmup() }
        Task { await localCleanupClient.removeRetiredModels() }
        CleanupModel.removeRetiredSettings()
        refreshModelCatalog()

        if hasCompletedSetup, isSelectedModelDownloaded, let selectedModelOption {
            Task {
                await warmModelTask(selectedModelOption)
                await recoverUnfinishedRecordings()
            }
            return
        }

        $hasCompletedSetup.withLock { $0 = false }
        beginOnboardingFlow()
        showOnboardingWindow()
    }

    func microphonePermissionButtonTapped() async {
        if isPreviewMode {
            microphonePermissionState = .authorized
            return
        }

        let granted = await permissionsClient.requestMicrophonePermission()
        await refreshPermissionStatusAsync()
        logClient.debug("AppModel", "Microphone permission request resolved. granted=\(granted), authorized=\(self.microphoneAuthorized)")

        guard !granted, !microphoneAuthorized else { return }

        if microphonePermissionState == .denied {
            await permissionsClient.openMicrophonePrivacySettings()
        }
    }

    func accessibilityPermissionButtonTapped() {
        if isPreviewMode {
            accessibilityAuthorized = true
            menuTransientMessage = nil
            return
        }

        Task {
            await permissionsClient.promptForAccessibilityPermission()
            await refreshPermissionStatusAsync()
            logClient.debug("AppModel", "Accessibility permission prompt shown. authorized=\(self.accessibilityAuthorized)")

            if !accessibilityAuthorized {
                await permissionsClient.openAccessibilityPrivacySettings()
                menuTransientMessage = "Turn on Accessibility access"
            }
        }
    }

    func copyTranscriptHistoryButtonTapped(_ entryID: UUID) {
        guard let entry = transcriptHistoryDays.lazy.compactMap({ $0.entries[id: entryID] }).first else { return }
        guard let transcript = historyClient.transcriptText(entry.preferredTranscriptRelativePath) else { return }
        guard transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return }
        pasteClient.copy(transcript)
        menuTransientMessage = nil
    }

    func deleteTranscriptHistoryButtonTapped(_ entryID: UUID) {
        let updatedDays = historyClient.deleteEntry(transcriptHistoryDays, entryID)
        $transcriptHistoryDays.withLock { $0 = updatedDays }
        menuTransientMessage = nil
    }

    func readyCleanupModel(for route: CleanupRoute?) -> CleanupModel? {
        let model = route?.cleanupModel ?? cleanupModel
        return isCleanupModelReady(model) ? model : nil
    }

    func isCleanupModelReady(_ model: CleanupModel) -> Bool {
        switch model {
        case .off: false
        case .appleIntelligence: foundationModelClient.isAvailable()
        case .petalW1: localCleanupClient.isDownloaded()
        case .cloud: cloudCleanup.configuration != nil
        }
    }

    func bootstrapHistory() async {
        let days = transcriptHistoryDays
        let healed = await Self.bootstrapHistory(days, retentionMode: historyRetentionMode, historyClient: historyClient)
        // A recording that finished meanwhile is newer than this copy, so healing waits for the next launch.
        guard healed != days, transcriptHistoryDays == days else { return }
        $transcriptHistoryDays.withLock { $0 = healed }
    }

    @concurrent
    nonisolated static func bootstrapHistory(
        _ days: [TranscriptHistoryDay],
        retentionMode: HistoryRetentionMode,
        historyClient: HistoryClient
    ) async -> [TranscriptHistoryDay] {
        historyClient.applyRetention(retentionMode, days)
    }

    func refreshModelCatalog() {
        let downloads = modelDownloadViewModel
        let catalog = ModelCatalogEntry.catalog { downloads.isModelDownloaded($0) }
        guard catalog != modelCatalog else { return }
        $modelCatalog.withLock { $0 = catalog }
    }

    public func handleDeepLink(_ command: PetalDeepLinkCommand) async {
        logClient.debug("AppModel", "Handling deep link command: \(command.rawValue)")
        switch command {
        case .start:
            await startRecordingFromDeepLink()
        case .stop:
            await stopRecordingFromDeepLink()
        case .toggle:
            await toggleRecordingFromDeepLink()
        case .setup:
            changeModelButtonTapped()
        case .settings:
            openSettingsWindow()
        case .checkForUpdates:
            break
        }
    }

    func beginOnboardingFlow() {
        guard onboardingModel == nil else { return }
        let model = withDependencies(from: self) {
            OnboardingModel(downloadViewModel: modelDownloadViewModel, cleanupDownload: cleanupDownload)
        }
        model.onCompleted = { [weak self] in
            Task { [weak self] in
                guard let self else { return }
                await finishOnboarding()
                selectedModelDidChange()
            }
        }
        model.onMinimize = { [weak self] in
            self?.minimizeToMiniDownload()
        }
        onboardingModel = model
    }

    func minimizeToMiniDownload() {
        guard !isShowingMiniDownload else { return }
        isShowingMiniDownload = true

        Task { [weak self, windowClient, modelDownloadViewModel] in
            await windowClient.close(WindowConfig.onboarding.id)
            await windowClient.show(.miniDownload, { [weak self] in
                SwiftUI.NSHostingView(rootView: MiniDownloadView(model: modelDownloadViewModel) { [weak self] in
                    self?.expandFromMiniDownload()
                })
            }, { [weak self] in
                self?.isShowingMiniDownload = false
            })
        }
    }

    func expandFromMiniDownload() {
        guard isShowingMiniDownload else { return }
        isShowingMiniDownload = false

        Task {
            await windowClient.close(WindowConfig.miniDownload.id)
            showOnboardingWindow()
        }
    }

    func finishOnboarding() async {
        isShowingMiniDownload = false
        onboardingModel = nil
        $hasCompletedSetup.withLock { $0 = true }
        registerShortcutHandlers()
        menuTransientMessage = nil
        await windowClient.close(WindowConfig.miniDownload.id)
        await windowClient.close(WindowConfig.onboarding.id)
    }

    func showOnboardingWindow() {
        if isPreviewMode { return }
        guard let onboardingModel else { return }

        Task {
            await windowClient.show(.onboarding, {
                SwiftUI.NSHostingView(rootView: OnboardingView(model: onboardingModel))
            }, {})
        }
    }

    func refreshPermissionStatusAsync() async {
        if isPreviewMode { return }
        // An equal value still notifies observers, so each property is written only when it changes.
        let microphoneState = await permissionsClient.microphonePermissionState()
        if microphonePermissionState != microphoneState {
            microphonePermissionState = microphoneState
            if microphoneAuthorized { prepareAudioCapture() }
        }
        let isAccessibilityAuthorized = await permissionsClient.hasAccessibilityPermission()
        if accessibilityAuthorized != isAccessibilityAuthorized {
            accessibilityAuthorized = isAccessibilityAuthorized
        }
    }

    func prepareAudioCapture() {
        guard !isPreviewMode, microphoneAuthorized else { return }
        audioClient.warmup(selectedModelOption?.supportsStreamingTranscription ?? false)
    }

    func startPermissionMonitoring() {
        permissionMonitorTask?.cancel()
        permissionMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshPermissionStatusAsync()
                let hasAllPermissions = self.microphoneAuthorized && self.accessibilityAuthorized
                try? await self.clock.sleep(for: .seconds(hasAllPermissions ? 10 : 1))
            }
        }
    }

    func warmModelTask(_ selectedModelOption: ModelOption) async {
        if isPreviewMode { return }
        logClient.debug("AppModel", "Warming model: \(selectedModelOption.rawValue)")

        do {
            try await transcriptionClient.prepareModelIfNeeded(selectedModelOption)
            logClient.debug("AppModel", "Model warmup complete: \(selectedModelOption.rawValue)")
        } catch is CancellationError {
            return
        } catch {
            reportIssue(error)
            logClient.error("AppModel", "Model warmup failed: \(error.localizedDescription)")
        }
    }

    func scheduleCopiedThenAccessibilityPrompt() {
        accessibilityFollowUpTask?.cancel()
        accessibilityFollowUpTask = Task { [weak self] in
            await self?.showCopiedThenAccessibilityPrompt()
        }
    }

    func cancelAccessibilityFollowUp() {
        accessibilityFollowUpTask?.cancel()
        accessibilityFollowUpTask = nil
    }

    func showCopiedThenAccessibilityPrompt() async {
        await floatingCapsuleClient.showCopiedToClipboard()
        do {
            try await clock.sleep(for: .seconds(3))
        } catch {
            return
        }
        guard !Task.isCancelled, case .idle = sessionState else { return }

        await floatingCapsuleClient.showAccessibilityPrompt { [permissionsClient] in
            Task {
                await permissionsClient.promptForAccessibilityPermission()
                await permissionsClient.openAccessibilityPrivacySettings()
            }
        }
        for _ in 0..<20 {
            do {
                try await clock.sleep(for: .milliseconds(500))
            } catch {
                return
            }
            guard !Task.isCancelled, case .idle = sessionState else { return }
            if await permissionsClient.hasAccessibilityPermission() {
                await floatingCapsuleClient.showAccessibilityEnabled()
                accessibilityAuthorized = true
                do {
                    try await clock.sleep(for: .seconds(2))
                } catch {
                    return
                }
                break
            }
        }
        guard !Task.isCancelled, case .idle = sessionState else { return }
        stopTranscriptionProgressTracking()
        await floatingCapsuleClient.hide()
        accessibilityFollowUpTask = nil
    }

    func prepareCleanupModelIfNeeded() {
        guard let model = ([cleanupModel] + router.routeCleanupModels).first(where: \.isLocal), cleanupWarmupTask == nil else { return }
        let client = localCleanupClient
        cleanupWarmupTask = Task { [weak self] in
            do {
                let prepared = try await Self.prepareCleanupModel(client)
                guard !Task.isCancelled else { return }
                if !prepared { self?.cleanupWarmupTask = nil }
            } catch {
                guard !Task.isCancelled else { return }
                self?.logClient.error("AppModel", "\(model.rawValue) warmup failed: \(error.localizedDescription)")
                self?.cleanupWarmupTask = nil
            }
        }
    }

    @concurrent
    nonisolated static func prepareCleanupModel(_ client: LocalCleanupClient) async throws -> Bool {
        guard client.isDownloaded() else { return false }
        try Task.checkCancellation()
        try await client.prepare()
        return true
    }

    func cleanupModelDidChange() {
        cleanupWarmupTask?.cancel()
        cleanupWarmupTask = nil
        Task { await localCleanupClient.unload() }
    }

    deinit {
        transcriptionProgressTask?.cancel()
        streamingTask?.cancel()
        cancelConfirmationTimerTask?.cancel()
        accessibilityFollowUpTask?.cancel()
        warmupTask?.cancel()
        cleanupWarmupTask?.cancel()
        permissionMonitorTask?.cancel()
        pasteLastTranscriptionTask?.cancel()
    }
}

extension AppModel {
    public static func makePreview(_ configure: (AppModel) -> Void = { _ in }) -> AppModel {
        withDependencies {
            $0.defaultAppStorage = UserDefaults(suiteName: UUID().uuidString)!
            $0.defaultFileStorage = .inMemory
        } operation: {
            let model = AppModel(isPreviewMode: true)
            model.$hasCompletedSetup.withLock { $0 = true }
            configure(model)
            return model
        }
    }
}
