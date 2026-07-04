import AppKit
import AVFoundation
import AudioClient
import class SwiftUI.NSHostingView
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
import os
import PasteClient
import PermissionsClient
import PlaybackDuckingClient
import Shared
import SoundClient
import TranscriptionClient
import UserNotifications
import WindowClient

@MainActor
@Observable
final class AppModel {
    enum ProcessingStage: Equatable {
        case trimming
        case speeding
        case transcribing
        case refining
    }

    enum SessionState: Equatable {
        case idle
        case recording
        case processing(ProcessingStage)
        case error(String)
    }

    @ObservationIgnored @Shared(.hasCompletedSetup) var hasCompletedSetup = false
    @ObservationIgnored @Shared(.transcriptionMode) var transcriptionMode: TranscriptionMode = .verbatim
    @ObservationIgnored @Shared(.smartPrompt) var smartPrompt = "Clean up filler words and repeated phrases. Return a polished version of what was said."
    @ObservationIgnored @Shared(.appleIntelligenceEnabled) var appleIntelligenceEnabled = false
    @ObservationIgnored @Shared(.compressHistoryAudio) var compressHistoryAudio = false
    @ObservationIgnored @Shared(.historyRetentionMode) var historyRetentionMode: HistoryRetentionMode = .both
    @ObservationIgnored @Shared(.pushToTalkThreshold) var pushToTalkThreshold: PushToTalkThreshold = .long
    @ObservationIgnored @Shared(.restoreClipboardAfterPaste) var restoreClipboardAfterPaste = true
    @ObservationIgnored @Shared(.duckSystemAudioDuringRecording) var duckSystemAudioDuringRecording = false
    @ObservationIgnored @Shared(.shortcutTriggerMode) var shortcutTriggerMode: ShortcutTriggerMode = .combo
    @ObservationIgnored @Shared(.doubleTapKey) var doubleTapKey: DoubleTapKey = .unconfigured
    @ObservationIgnored @Shared(.doubleTapInterval) var doubleTapInterval: Double = 0.4
    @ObservationIgnored @Shared(.transcriptHistoryDays) var transcriptHistoryDays: [TranscriptHistoryDay] = []

    let modelDownloadViewModel: ModelDownloadModel

    var selectedModelID: String {
        get { modelDownloadViewModel.selectedModelID }
        set {
            modelDownloadViewModel.$selectedModelID.withLock { $0 = newValue }
            selectedModelDidChange()
        }
    }

    var sessionState: SessionState = .idle
    /// Smoothed microphone input level (0...1) for the menu bar pixel pulse.
    var currentLevel: Double = 0
    var lastError: String?
    var transientMessage: String?
    var isWarmingModel = false
    var microphonePermissionState: MicrophonePermissionState = .notDetermined
    var microphoneAuthorized = false
    var accessibilityAuthorized = false

    var onboardingModel: OnboardingModel?

    @ObservationIgnored @Dependency(\.continuousClock) private var clock
    @ObservationIgnored @Dependency(\.date.now) private var now
    @ObservationIgnored @Dependency(\.uuid) private var uuid
    @ObservationIgnored @Dependency(\.transcriptionClient) private var transcriptionClient
    @ObservationIgnored @Dependency(\.pasteClient) private var pasteClient
    @ObservationIgnored @Dependency(\.permissionsClient) private var permissionsClient
    @ObservationIgnored @Dependency(\.audioClient) private var audioClient
    @ObservationIgnored @Dependency(\.keyboardClient) private var keyboardClient
    @ObservationIgnored @Dependency(\.floatingCapsuleClient) private var floatingCapsuleClient
    @ObservationIgnored @Dependency(\.soundClient) private var soundClient
    @ObservationIgnored @Dependency(\.historyClient) private var historyClient
    @ObservationIgnored @Dependency(\.logClient) private var logClient
    @ObservationIgnored @Dependency(\.foundationModelClient) private var foundationModelClient
    @ObservationIgnored @Dependency(\.doubleTapClient) private var doubleTapClient
    @ObservationIgnored @Dependency(\.windowClient) private var windowClient
    @ObservationIgnored @Dependency(\.playbackDuckingClient) private var playbackDuckingClient
    @ObservationIgnored private let logger = Logger(subsystem: "com.optimalapps.petal", category: "AppModel")

    @ObservationIgnored private let isPreviewMode: Bool

    @ObservationIgnored private var didBootstrap = false
    @ObservationIgnored private var pushToTalkIsActive = false
    @ObservationIgnored private var toggleRecordingIsActive = false
    @ObservationIgnored private var isAwaitingCancelRecordingConfirmation = false
    @ObservationIgnored private var cancelConfirmationTimerTask: Task<Void, Never>?
    @ObservationIgnored private var ignoreNextShortcutKeyUp = false
    @ObservationIgnored private var currentShortcutPressStart: Date?
    @ObservationIgnored private var isStartingRecording = false
    @ObservationIgnored private var isStoppingRecording = false
    @ObservationIgnored private var isTranscribingDroppedFile = false
    @ObservationIgnored private var pendingStopAfterStart = false
    @ObservationIgnored private var transcriptionProgressTask: Task<Void, Never>?
    @ObservationIgnored private var permissionMonitorTask: Task<Void, Never>?
    @ObservationIgnored private var miniDownloadRestoreTask: Task<Void, Never>?
    @ObservationIgnored private var warmupTask: Task<Void, Never>?
    @ObservationIgnored private var menuBarFlashTask: Task<Void, Never>?
    @ObservationIgnored private var downloadStateObserverTask: Task<Void, Never>?
    @ObservationIgnored private var isShowingMiniDownload = false
    @ObservationIgnored private var activeHistorySessionID: UUID?
    @ObservationIgnored private var isPlaybackDucked = false
    var menuBarFlashOn = true
    @ObservationIgnored private var estimatedTranscriptionRTF = 2.2
    private var toggleActivationThresholdSeconds: Double { pushToTalkThreshold.seconds }
    nonisolated private static let deepLinkStartTimeoutSeconds = 12.0

    nonisolated private static var isRunningInSwiftUIPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    nonisolated private static var isRunningUnattendedE2E: Bool {
        if ProcessInfo.processInfo.environment["PETAL_UNATTENDED_E2E"] == "1" {
            return true
        }
        return UserDefaults.standard.bool(forKey: "unattended_e2e_mode")
    }

    init(isPreviewMode: Bool = AppModel.isRunningInSwiftUIPreview) {
        self.isPreviewMode = isPreviewMode
        modelDownloadViewModel = ModelDownloadModel(isPreviewMode: isPreviewMode)

        if isPreviewMode {
            $hasCompletedSetup.withLock { $0 = true }
            selectedModelID = ModelOption.defaultOption.rawValue
            microphonePermissionState = .authorized
            microphoneAuthorized = true
            accessibilityAuthorized = true
            return
        }

        modelDownloadViewModel.onDownloadCompleted = { [weak self] in
            guard let self, self.hasCompletedSetup else { return }
            self.warmupTask?.cancel()
            self.isWarmingModel = true
            self.transientMessage = "Warming up \(self.selectedModelOption?.displayName ?? "model")…"
            self.warmupTask = Task { [weak self] in
                guard let self else { return }
                await self.warmModelTask()
                if !Task.isCancelled {
                    self.isWarmingModel = false
                    if self.transientMessage?.contains("Warming") == true {
                        self.transientMessage = nil
                    }
                }
            }
        }

        $transcriptHistoryDays.withLock { $0 = historyClient.bootstrap(historyRetentionMode, $0) }

        registerShortcutHandlers()
        registerKeyboardMonitor()
        refreshPermissionStatus()
        startPermissionMonitoring()
        audioClient.warmup()
        logger.info("AppModel initialized. setupCompleted=\(self.hasCompletedSetup, privacy: .public), model=\(self.selectedModelID, privacy: .public)")
        consoleLog("AppModel initialized. setupCompleted=\(self.hasCompletedSetup), model=\(self.selectedModelID)")

        Task { await appDidLaunch() }
    }

    // MARK: - Computed Properties

    var selectedModelOption: ModelOption? {
        ModelOption(rawValue: selectedModelID)
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

    var menuBarSymbolName: String {
        if modelDownloadViewModel.state.isActive || modelDownloadViewModel.state.isPaused {
            return menuBarFlashOn ? "arrow.down.circle.dotted" : "arrow.down.circle"
        }

        switch sessionState {
        case .idle: return "waveform.badge.mic"
        case .recording: return "record.circle.fill"
        case let .processing(stage):
            switch stage {
            case .trimming: return "scissors"
            case .speeding: return "figure.run"
            case .transcribing: return "hourglass"
            case .refining: return "apple.intelligence"
            }
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    /// Visual state for the animated pixel menu bar icon.
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

    var recentTranscriptHistoryEntries: [TranscriptHistoryEntry] {
        transcriptHistoryDays
            .flatMap(\.entries)
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(20)
            .map { $0 }
    }

    // MARK: - Setup

    func selectedModelDidChange() {
        modelDownloadViewModel.selectedModelChanged()
        estimatedTranscriptionRTF = defaultTranscriptionRTF(for: selectedModelOption)
        let normalizedMode = normalizedTranscriptionMode(transcriptionMode)
        if transcriptionMode != normalizedMode {
            $transcriptionMode.withLock { $0 = normalizedMode }
        }
        guard hasCompletedSetup, isSelectedModelDownloaded else { return }
        warmupTask?.cancel()
        isWarmingModel = true
        transientMessage = "Warming up \(selectedModelOption?.displayName ?? "model")…"
        warmupTask = Task {
            await transcriptionClient.unloadModel()
            await warmModelTask()
            if !Task.isCancelled {
                isWarmingModel = false
                if transientMessage?.contains("Warming") == true {
                    transientMessage = nil
                }
            }
        }
    }

    func changeModelButtonTapped() {
        if isPreviewMode { return }
        beginOnboardingFlow()
        showOnboardingWindow()
    }

    func openSettingsWindow() {
        if isPreviewMode { return }
        showSettingsWindow()
    }

    // MARK: - Lifecycle

    func appDidLaunch() async {
        if isPreviewMode { return }
        guard !didBootstrap else { return }
        didBootstrap = true
        logger.info("App did launch. setupCompleted=\(self.hasCompletedSetup, privacy: .public), modelDownloaded=\(self.isSelectedModelDownloaded, privacy: .public)")
        consoleLog("App did launch. setupCompleted=\(self.hasCompletedSetup), modelDownloaded=\(self.isSelectedModelDownloaded)")

        // Pre-warm sound players in background so first recording
        // feedback is instant.
        Task { await soundClient.warmup() }

        if hasCompletedSetup, isSelectedModelDownloaded {
            Task { await warmModelTask() }
            return
        }

        $hasCompletedSetup.withLock { $0 = false }
        beginOnboardingFlow()
        try? await clock.sleep(for: .milliseconds(150))
        showOnboardingWindow()
    }

    // MARK: - Permissions (runtime)

    func microphonePermissionButtonTapped() async {
        if isPreviewMode {
            microphonePermissionState = .authorized
            microphoneAuthorized = true
            lastError = nil
            return
        }

        let granted = await permissionsClient.requestMicrophonePermission()
        await refreshPermissionStatusAsync()
        logger.info("Microphone permission request resolved. granted=\(granted, privacy: .public), authorized=\(self.microphoneAuthorized, privacy: .public)")
        consoleLog("Microphone permission request resolved. granted=\(granted), authorized=\(self.microphoneAuthorized)")

        if granted || microphoneAuthorized {
            lastError = nil
            return
        }

        if microphonePermissionState == .denied {
            await permissionsClient.openMicrophonePrivacySettings()
            lastError = "Turn on microphone access"
            return
        }

        lastError = "Turn on microphone access"
    }

    func accessibilityPermissionButtonTapped() {
        if isPreviewMode {
            accessibilityAuthorized = true
            transientMessage = nil
            return
        }

        Task {
            await permissionsClient.promptForAccessibilityPermission()
            await refreshPermissionStatusAsync()
            logger.info("Accessibility permission prompt shown. authorized=\(self.accessibilityAuthorized, privacy: .public)")
            consoleLog("Accessibility permission prompt shown. authorized=\(self.accessibilityAuthorized)")

            if !accessibilityAuthorized {
                await permissionsClient.openAccessibilityPrivacySettings()
                transientMessage = "Turn on Accessibility access"
            }
        }
    }

    // MARK: - History

    func copyTranscriptHistoryButtonTapped(_ entryID: UUID) {
        guard let entry = transcriptHistoryDays.lazy.compactMap({ $0.entries[id: entryID] }).first else { return }
        let transcript = formattedHistoryEntry(entry)
        guard transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return }
        copyTranscriptToClipboard(transcript)
        transientMessage = "Copied to clipboard"
    }

    // MARK: - Dropped Files

    func droppedAudioFileRejected(_ error: AudioFileDropValidationError) {
        switch error {
        case .noFile:
            transientMessage = "Drop an audio file to transcribe"
        case .multipleFiles:
            transientMessage = "Drop one file at a time"
        case .unsupportedFile:
            transientMessage = "File type not supported"
        case .directory:
            transientMessage = "Drop a file, not a folder"
        }
    }

    func transcribeDroppedAudioFile(_ audioURL: URL) async {
        guard hasCompletedSetup else {
            transientMessage = "Finish setup to transcribe"
            beginOnboardingFlow()
            showOnboardingWindow()
            return
        }

        guard !isTranscribingDroppedFile else {
            transientMessage = "Already transcribing a file"
            return
        }

        let isCurrentlyRecording = await audioClient.isRecording()
        guard !isCurrentlyRecording, !isRecordingLifecycleBusy else {
            transientMessage = "Finish the current one first"
            return
        }

        guard let selectedModelOption else {
            sessionState = .error(AppTranscriptionError.pipelineUnavailable.localizedDescription)
            transientMessage = "Transcription unavailable"
            return
        }

        isTranscribingDroppedFile = true
        defer { isTranscribingDroppedFile = false }

        let didStartSecurityScope = audioURL.startAccessingSecurityScopedResource()
        defer {
            if didStartSecurityScope {
                audioURL.stopAccessingSecurityScopedResource()
            }
        }

        sessionState = .processing(.trimming)
        await floatingCapsuleClient.showTrimming()

        let historySessionID = uuid()
        let pipelineStart = now
        let transcriptionStart = now
        var pipelineStage = "file-setup"

        do {
            let normalizedAudioURL = try await normalizeDroppedAudioFileForTranscription(audioURL)
            defer { try? FileManager.default.removeItem(at: normalizedAudioURL) }

            let audioDuration = transcriptionClient.audioDurationSeconds(normalizedAudioURL)
            let audioSizeBytes = appAudioFileSizeBytes(audioURL) ?? 0

            logClient.dumpDebug(
                "AppModel",
                "Dropped file transcription started",
                appDumpString(
                    [
                        "sessionID": historySessionID.uuidString,
                        "model": selectedModelOption.rawValue,
                        "modeRequested": transcriptionMode.rawValue,
                        "audioFile": audioURL.lastPathComponent,
                        "audioDuration": formatElapsedSeconds(audioDuration),
                        "audioSizeBytes": "\(audioSizeBytes)"
                    ]
                )
            )

            if autoSpeedRate(for: audioDuration) != nil {
                sessionState = .processing(.speeding)
                await floatingCapsuleClient.showSpeeding()
            }

            pipelineStage = "transcribing"
            sessionState = .processing(.transcribing)
            await floatingCapsuleClient.showTranscribing()
            await soundClient.playTranscriptionStarted()
            startTranscriptionProgressTracking(audioDuration: audioDuration)

            let mode = normalizedTranscriptionMode(transcriptionMode)
            if transcriptionMode != mode {
                $transcriptionMode.withLock { $0 = mode }
            }

            var transcript = try await transcriptionClient.transcribe(
                normalizedAudioURL,
                selectedModelOption,
                mode,
                mode == .smart ? smartPrompt : nil
            )
            let originalTranscript = transcript
            var shouldPersistOriginalVariant = false
            let transcriptionElapsed = now.timeIntervalSince(transcriptionStart)
            updateTranscriptionSpeedEstimate(audioDuration: audioDuration, elapsed: transcriptionElapsed)
            stopTranscriptionProgressTracking(finalProgress: 1)

            let needsAIRefine = mode == .smart
                && !selectedModelOption.supportsSmartTranscription
                && appleIntelligenceEnabled
                && foundationModelClient.isAvailable()
                && !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            if needsAIRefine {
                pipelineStage = "refining"
                sessionState = .processing(.refining)
                await soundClient.playRefineStarted()
                await floatingCapsuleClient.showRefining()

                if let refined = try? await foundationModelClient.refine(transcript, smartPrompt),
                   !refined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    shouldPersistOriginalVariant = refined != transcript
                    transcript = refined
                }
            }

            let isEmptyTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let persistedPaths = await persistHistoryArtifacts(
                audioURL: audioURL,
                transcript: transcript,
                timestamp: transcriptionStart,
                mode: mode.rawValue,
                modelID: selectedModelOption.rawValue
            )

            if isEmptyTranscript {
                pipelineStage = "persist-empty"
                await soundClient.playTranscriptionNoResult()
                transientMessage = "No speech detected"

                appendTranscriptHistory(
                    transcript: transcript,
                    modelID: selectedModelOption.rawValue,
                    mode: mode.rawValue,
                    audioDuration: audioDuration,
                    transcriptionElapsed: transcriptionElapsed,
                    pasteResult: .skipped,
                    audioRelativePath: persistedPaths?.audioRelativePath,
                    transcriptRelativePath: persistedPaths?.transcriptRelativePath,
                    sessionID: historySessionID
                )
            } else {
                pipelineStage = "clipboard"
                await soundClient.playTranscriptionCompleted()
                copyTranscriptToClipboard(transcript)
                await postCopiedToClipboardNotification(body: "Copied to clipboard")
                await floatingCapsuleClient.showCopiedToClipboard()
                transientMessage = "Copied to clipboard"

                appendTranscriptHistory(
                    transcript: transcript,
                    modelID: selectedModelOption.rawValue,
                    mode: mode.rawValue,
                    audioDuration: audioDuration,
                    transcriptionElapsed: transcriptionElapsed,
                    pasteResult: .copiedOnly,
                    audioRelativePath: persistedPaths?.audioRelativePath,
                    transcriptRelativePath: persistedPaths?.transcriptRelativePath,
                    sessionID: historySessionID
                )

                if shouldPersistOriginalVariant {
                    let originalPaths = await persistHistoryArtifacts(
                        audioURL: audioURL,
                        transcript: originalTranscript,
                        timestamp: transcriptionStart,
                        mode: "original",
                        modelID: selectedModelOption.rawValue,
                        persistAudio: false
                    )
                    appendTranscriptHistory(
                        transcript: originalTranscript,
                        modelID: selectedModelOption.rawValue,
                        mode: "original",
                        audioDuration: audioDuration,
                        transcriptionElapsed: transcriptionElapsed,
                        pasteResult: .skipped,
                        audioRelativePath: originalPaths?.audioRelativePath,
                        transcriptRelativePath: originalPaths?.transcriptRelativePath,
                        sessionID: historySessionID
                    )
                }
            }

            lastError = nil
            sessionState = .idle
            let pipelineElapsed = now.timeIntervalSince(pipelineStart)
            logClient.dumpDebug(
                "AppModel",
                "Dropped file transcription completed",
                appDumpString(
                    [
                        "sessionID": historySessionID.uuidString,
                        "elapsed": formatElapsedSeconds(pipelineElapsed),
                        "finalStage": pipelineStage
                    ]
                )
            )
        } catch {
            reportIssue(error)
            lastError = error.localizedDescription
            transientMessage = "Transcription failed"
            sessionState = .error(error.localizedDescription)
            stopTranscriptionProgressTracking()
            await floatingCapsuleClient.showError("Transcription failed")
            logger.error("Dropped file transcription failed: \(error.localizedDescription, privacy: .public)")
            logClient.error(
                "AppModel",
                "Dropped file transcription failed. sessionID=\(historySessionID.uuidString), stage=\(pipelineStage), error=\(error.localizedDescription)"
            )
        }

        await hideCapsuleAfterDelay()
    }

    // MARK: - Deep Links

    func handleDeepLink(_ command: PetalDeepLinkCommand) async {
        logger.info("Handling deep link command: \(command.rawValue, privacy: .public)")
        consoleLog("Handling deep link command: \(command.rawValue)")
        switch command {
        case .start:
            await startRecordingFromDeepLink()
        case .stop:
            await stopRecordingFromDeepLink()
        case .toggle:
            await toggleRecordingFromDeepLink()
        case .setup:
            changeModelButtonTapped()
        case .checkForUpdates:
            logger.debug("check-for-updates deep link is handled by Sparkle updater controller")
        }
    }

    // MARK: - Push to Talk

    func pushToTalkKeyDown() async {
        logger.info("Push-to-talk key down")
        consoleLog("Push-to-talk key down")

        if isAwaitingCancelRecordingConfirmation {
            dismissCancelRecordingConfirmation()
        }

        guard hasCompletedSetup else {
            transientMessage = "Finish setup to record"
            beginOnboardingFlow()
            showOnboardingWindow()
            return
        }

        if toggleRecordingIsActive {
            guard !isStoppingRecording else {
                logger.debug("Ignoring toggle stop: stop already in flight")
                return
            }
            toggleRecordingIsActive = false
            ignoreNextShortcutKeyUp = true
            logger.info("Toggle recording stop requested")
            consoleLog("Toggle recording stop requested")
            await stopRecordingAndTranscribe()
            return
        }

        if isRecordingLifecycleBusy {
            logger.debug("Ignoring key down while recording lifecycle is busy")
            return
        }

        guard !pushToTalkIsActive else { return }

        pushToTalkIsActive = true
        pendingStopAfterStart = false
        currentShortcutPressStart = now

        if !microphoneAuthorized {
            await microphonePermissionButtonTapped()
            await refreshPermissionStatusAsync()

            guard microphoneAuthorized else {
                sessionState = .error("Microphone permission denied")
                transientMessage = "Turn on microphone access"
                pushToTalkIsActive = false
                currentShortcutPressStart = nil
                await floatingCapsuleClient.showError("Microphone denied")
                await hideCapsuleAfterDelay()
                return
            }
        }

        isStartingRecording = true
        defer { isStartingRecording = false }

        do {
            try await audioClient.startRecording { [weak self] level in
                guard let self else { return }
                Task { @MainActor [self, level] in
                    self.recordingLevelDidUpdate(level)
                }
            }

            isAwaitingCancelRecordingConfirmation = false
            sessionState = .recording
            activeHistorySessionID = uuid()
            await startPlaybackDuckingIfNeeded()
            logger.info("Recording started")
            consoleLog("Recording started")

            // Fire-and-forget: don't block the recording start path on
            // sound playback and capsule animation.
            Task {
                await soundClient.playRecordingStarted()
            }
            await floatingCapsuleClient.showRecording()

            if pendingStopAfterStart {
                pendingStopAfterStart = false
                logger.debug("Applying deferred stop after recording start completed")
                await stopRecordingAndTranscribe()
                return
            }
        } catch {
            reportIssue(error)
            sessionState = .error(error.localizedDescription)
            lastError = error.localizedDescription
            pushToTalkIsActive = false
            currentShortcutPressStart = nil
            await floatingCapsuleClient.showError("Recording failed")
            logger.error("Recording failed to start: \(error.localizedDescription, privacy: .public)")
            consoleLog("Recording failed to start: \(error.localizedDescription)")
            await hideCapsuleAfterDelay()
        }
    }

    func pushToTalkKeyUp() async {
        logger.info("Push-to-talk key up")
        consoleLog("Push-to-talk key up")

        if isAwaitingCancelRecordingConfirmation { return }

        if ignoreNextShortcutKeyUp {
            ignoreNextShortcutKeyUp = false
            logger.debug("Ignoring key up after toggle stop")
            return
        }

        guard pushToTalkIsActive else { return }

        pushToTalkIsActive = false

        if isStoppingRecording {
            logger.debug("Ignoring key up while stop is already in flight")
            return
        }

        let holdDuration = now.timeIntervalSince(currentShortcutPressStart ?? now)
        currentShortcutPressStart = nil

        let isCurrentlyRecording = await audioClient.isRecording()
        if !isCurrentlyRecording {
            guard isStartingRecording else { return }
            if holdDuration < toggleActivationThresholdSeconds {
                toggleRecordingIsActive = true
                transientMessage = "Listening — tap your shortcut to stop."
                logger.info("Toggle recording engaged while start in progress. holdDuration=\(holdDuration, privacy: .public)")
                let holdDurationText = holdDuration.formatted(.number.precision(.fractionLength(2)))
                consoleLog("Toggle recording engaged while start in progress. holdDuration=\(holdDurationText)s")
                return
            }

            pendingStopAfterStart = true
            logger.debug("Deferring stop request until recording start completes")
            return
        }

        if holdDuration < toggleActivationThresholdSeconds {
            toggleRecordingIsActive = true
            transientMessage = "Listening — tap your shortcut to stop."
            logger.info("Toggle recording engaged. holdDuration=\(holdDuration, privacy: .public)")
            let holdDurationText = holdDuration.formatted(.number.precision(.fractionLength(2)))
            consoleLog("Toggle recording engaged. holdDuration=\(holdDurationText)s")
            return
        }

        await stopRecordingAndTranscribe()
    }

    // MARK: - Private: Recording & Transcription

    private func stopRecordingAndTranscribe() async {
        guard !isStoppingRecording else {
            logger.debug("Ignoring stop request while stop is already in flight")
            return
        }
        isStoppingRecording = true
        defer { isStoppingRecording = false }

        let isCurrentlyRecording = await audioClient.isRecording()
        guard isCurrentlyRecording else {
            logger.debug("Ignoring stop request because no recording is active")
            pushToTalkIsActive = false
            toggleRecordingIsActive = false
            activeHistorySessionID = nil
            sessionState = .idle
            await stopPlaybackDuckingIfNeeded()
            await floatingCapsuleClient.hide()
            return
        }

        toggleRecordingIsActive = false
        isAwaitingCancelRecordingConfirmation = false
        sessionState = .processing(.trimming)
        await floatingCapsuleClient.showTrimming()
        let historySessionID = activeHistorySessionID ?? uuid()
        defer { activeHistorySessionID = nil }
        let pipelineStart = now
        var pipelineStage = "stop-recording"

        do {
            let stopRecordingStart = now
            let audioURL = try await audioClient.stopRecording()
            await stopPlaybackDuckingIfNeeded()
            defer { try? FileManager.default.removeItem(at: audioURL) }
            let stopRecordingElapsed = now.timeIntervalSince(stopRecordingStart)
            let audioSizeBytes = appAudioFileSizeBytes(audioURL) ?? 0

            guard let selectedModelOption else {
                throw AppTranscriptionError.pipelineUnavailable
            }

            let audioDuration = transcriptionClient.audioDurationSeconds(audioURL)
            let expectedDuration = estimatedTranscriptionDuration(for: audioDuration)

            logClient.dumpDebug(
                "AppModel",
                "Transcription pipeline started",
                appDumpString(
                    [
                        "sessionID": historySessionID.uuidString,
                        "model": selectedModelOption.rawValue,
                        "modeRequested": transcriptionMode.rawValue,
                        "audioFile": audioURL.lastPathComponent,
                        "audioDuration": formatElapsedSeconds(audioDuration),
                        "audioSizeBytes": "\(audioSizeBytes)",
                        "captureStopElapsed": formatElapsedSeconds(stopRecordingElapsed),
                        "expectedTranscriptionDuration": formatElapsedSeconds(expectedDuration)
                    ]
                )
            )

            if autoSpeedRate(for: audioDuration) != nil {
                sessionState = .processing(.speeding)
                await floatingCapsuleClient.showSpeeding()
            }

            pipelineStage = "transcribing"
            sessionState = .processing(.transcribing)
            await floatingCapsuleClient.showTranscribing()
            await soundClient.playTranscriptionStarted()
            startTranscriptionProgressTracking(audioDuration: audioDuration)
            let transcriptionStart = now
            let mode = normalizedTranscriptionMode(transcriptionMode)
            logger.info("Mode normalization: requested=\(self.transcriptionMode.rawValue, privacy: .public), resolved=\(mode.rawValue, privacy: .public), model=\(selectedModelOption.rawValue, privacy: .public)")
            if transcriptionMode != mode {
                $transcriptionMode.withLock { $0 = mode }
            }

            let transcriptionCallStart = now
            var transcript = try await transcriptionClient.transcribe(
                audioURL,
                selectedModelOption,
                mode,
                mode == .smart ? smartPrompt : nil
            )
            let transcriptionCallElapsed = now.timeIntervalSince(transcriptionCallStart)
            let originalTranscript = transcript
            var shouldPersistOriginalVariant = false
            let transcriptionElapsed = now.timeIntervalSince(transcriptionStart)
            updateTranscriptionSpeedEstimate(audioDuration: audioDuration, elapsed: transcriptionElapsed)
            stopTranscriptionProgressTracking(finalProgress: 1)

            logClient.dumpDebug(
                "AppModel",
                "Transcription backend returned",
                appDumpString(
                    [
                        "sessionID": historySessionID.uuidString,
                        "modeResolved": mode.rawValue,
                        "transcriptionCallElapsed": formatElapsedSeconds(transcriptionCallElapsed),
                        "transcriptionTotalElapsed": formatElapsedSeconds(transcriptionElapsed),
                        "outputCharacters": "\(transcript.count)"
                    ]
                )
            )

            // Post-process with Apple Intelligence when smart mode is requested
            // and the model doesn't natively support it.
            let needsAIRefine = mode == .smart
                && !selectedModelOption.supportsSmartTranscription
                && appleIntelligenceEnabled
                && foundationModelClient.isAvailable()
                && !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            logger.info("Refine decision: mode=\(mode.rawValue, privacy: .public), modelSupportsSmartNatively=\(selectedModelOption.supportsSmartTranscription, privacy: .public), aiEnabled=\(self.appleIntelligenceEnabled, privacy: .public), aiAvailable=\(self.foundationModelClient.isAvailable(), privacy: .public), willRefine=\(needsAIRefine, privacy: .public)")

            if needsAIRefine {
                pipelineStage = "refining"
                sessionState = .processing(.refining)
                await soundClient.playRefineStarted()
                await floatingCapsuleClient.showRefining()
                logger.info("Starting Apple Intelligence refinement: inputLength=\(transcript.count, privacy: .public)")
                let refineStart = now

                if let refined = try? await foundationModelClient.refine(transcript, smartPrompt),
                   !refined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    let refineElapsed = now.timeIntervalSince(refineStart)
                    logger.info("Apple Intelligence refinement succeeded: outputLength=\(refined.count, privacy: .public)")
                    shouldPersistOriginalVariant = refined != transcript
                    transcript = refined
                    logClient.dumpDebug(
                        "AppModel",
                        "Refinement succeeded",
                        appDumpString(
                            [
                                "sessionID": historySessionID.uuidString,
                                "elapsed": formatElapsedSeconds(refineElapsed),
                                "outputCharacters": "\(refined.count)"
                            ]
                        )
                    )
                } else {
                    let refineElapsed = now.timeIntervalSince(refineStart)
                    logger.warning("Apple Intelligence refinement returned empty or failed, keeping original transcript")
                    logClient.dumpDebug(
                        "AppModel",
                        "Refinement skipped/failed",
                        appDumpString(
                            [
                                "sessionID": historySessionID.uuidString,
                                "elapsed": formatElapsedSeconds(refineElapsed)
                            ]
                        )
                    )
                }
            }

            let isEmptyTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            if isEmptyTranscript {
                pipelineStage = "persist-empty"
                await soundClient.playTranscriptionNoResult()
                transientMessage = "No speech detected"
                logger.info("Empty transcription result — no speech detected")
                consoleLog("Empty transcription result — no speech detected")

                let persistStart = now
                let persistedPaths = await persistHistoryArtifacts(
                    audioURL: audioURL,
                    transcript: transcript,
                    timestamp: transcriptionStart,
                    mode: mode.rawValue,
                    modelID: selectedModelOption.rawValue
                )
                let persistElapsed = now.timeIntervalSince(persistStart)
                logClient.dumpDebug(
                    "AppModel",
                    "Persisted empty transcript artifacts",
                    appDumpString(
                        [
                            "sessionID": historySessionID.uuidString,
                            "elapsed": formatElapsedSeconds(persistElapsed),
                            "audioPath": persistedPaths?.audioRelativePath ?? "nil",
                            "transcriptPath": persistedPaths?.transcriptRelativePath ?? "nil"
                        ]
                    )
                )

                appendTranscriptHistory(
                    transcript: transcript,
                    modelID: selectedModelOption.rawValue,
                    mode: mode.rawValue,
                    audioDuration: audioDuration,
                    transcriptionElapsed: transcriptionElapsed,
                    pasteResult: .skipped,
                    audioRelativePath: persistedPaths?.audioRelativePath,
                    transcriptRelativePath: persistedPaths?.transcriptRelativePath,
                    sessionID: historySessionID
                )
            } else {
                pipelineStage = "paste"
                await soundClient.playTranscriptionCompleted()

                let pasteStart = now
                let pasteResult = await pasteClient.paste(transcript, restoreClipboardAfterPaste)
                let pasteElapsed = now.timeIntervalSince(pasteStart)
                logger.info("Transcription completed. characters=\(transcript.count, privacy: .public), pasteResult=\(String(describing: pasteResult), privacy: .public)")
                consoleLog("Transcription completed. characters=\(transcript.count), pasteResult=\(String(describing: pasteResult))")
                logClient.dumpDebug(
                    "AppModel",
                    "Paste step",
                    appDumpString(
                        [
                            "sessionID": historySessionID.uuidString,
                            "pasteResult": pasteResult.rawValue,
                            "elapsed": formatElapsedSeconds(pasteElapsed),
                            "restoreClipboardAfterPaste": "\(restoreClipboardAfterPaste)"
                        ]
                    )
                )
                logClient.dumpDebug(
                    "AppModel",
                    "Transcription metrics",
                    appDumpString(
                        [
                            "characters": "\(transcript.count)",
                            "audioDuration": audioDuration.formatted(.number.precision(.fractionLength(2))),
                            "transcriptionElapsed": transcriptionElapsed.formatted(.number.precision(.fractionLength(2))),
                            "pasteResult": pasteResult.rawValue,
                            "sessionID": historySessionID.uuidString
                        ]
                    )
                )

                pipelineStage = "persist"
                let persistStart = now
                let persistedPaths = await persistHistoryArtifacts(
                    audioURL: audioURL,
                    transcript: transcript,
                    timestamp: transcriptionStart,
                    mode: mode.rawValue,
                    modelID: selectedModelOption.rawValue
                )
                let persistElapsed = now.timeIntervalSince(persistStart)
                logClient.dumpDebug(
                    "AppModel",
                    "Persisted transcript artifacts",
                    appDumpString(
                        [
                            "sessionID": historySessionID.uuidString,
                            "elapsed": formatElapsedSeconds(persistElapsed),
                            "audioPath": persistedPaths?.audioRelativePath ?? "nil",
                            "transcriptPath": persistedPaths?.transcriptRelativePath ?? "nil"
                        ]
                    )
                )

                appendTranscriptHistory(
                    transcript: transcript,
                    modelID: selectedModelOption.rawValue,
                    mode: mode.rawValue,
                    audioDuration: audioDuration,
                    transcriptionElapsed: transcriptionElapsed,
                    pasteResult: pasteResult,
                    audioRelativePath: persistedPaths?.audioRelativePath,
                    transcriptRelativePath: persistedPaths?.transcriptRelativePath,
                    sessionID: historySessionID
                )

                if shouldPersistOriginalVariant {
                    pipelineStage = "persist-original"
                    let originalPersistStart = now
                    let originalPaths = await persistHistoryArtifacts(
                        audioURL: audioURL,
                        transcript: originalTranscript,
                        timestamp: transcriptionStart,
                        mode: "original",
                        modelID: selectedModelOption.rawValue,
                        persistAudio: false
                    )
                    let originalPersistElapsed = now.timeIntervalSince(originalPersistStart)
                    logClient.dumpDebug(
                        "AppModel",
                        "Persisted original transcript variant",
                        appDumpString(
                            [
                                "sessionID": historySessionID.uuidString,
                                "elapsed": formatElapsedSeconds(originalPersistElapsed),
                                "transcriptPath": originalPaths?.transcriptRelativePath ?? "nil"
                            ]
                        )
                    )

                    appendTranscriptHistory(
                        transcript: originalTranscript,
                        modelID: selectedModelOption.rawValue,
                        mode: "original",
                        audioDuration: audioDuration,
                        transcriptionElapsed: transcriptionElapsed,
                        pasteResult: .skipped,
                        audioRelativePath: originalPaths?.audioRelativePath,
                        transcriptRelativePath: originalPaths?.transcriptRelativePath,
                        sessionID: historySessionID
                    )
                }

                switch pasteResult {
                case .pasted:
                    transientMessage = nil
                case .copiedOnly:
                    transientMessage = "Accessibility access is needed to paste. Turn it on in System Settings, then try again."
                    await postPasteFallbackNotification()
                    lastError = nil
                    sessionState = .idle
                    await showCopiedThenAccessibilityPrompt()
                    return
                case .skipped:
                    break
                }
            }

            lastError = nil
            sessionState = .idle
            let pipelineElapsed = now.timeIntervalSince(pipelineStart)
            logClient.dumpDebug(
                "AppModel",
                "Transcription pipeline completed",
                appDumpString(
                    [
                        "sessionID": historySessionID.uuidString,
                        "elapsed": formatElapsedSeconds(pipelineElapsed),
                        "finalStage": pipelineStage
                    ]
                )
            )
        } catch {
            await stopPlaybackDuckingIfNeeded()
            reportIssue(error)
            lastError = error.localizedDescription
            transientMessage = "Transcription failed"
            sessionState = .error(error.localizedDescription)
            stopTranscriptionProgressTracking()
            await floatingCapsuleClient.showError("Transcription failed")
            logger.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
            consoleLog("Transcription failed: \(error.localizedDescription)")
            let pipelineElapsed = now.timeIntervalSince(pipelineStart)
            logClient.error(
                "AppModel",
                "Transcription pipeline failed. sessionID=\(historySessionID.uuidString), stage=\(pipelineStage), elapsed=\(formatElapsedSeconds(pipelineElapsed)), error=\(error.localizedDescription)"
            )
        }

        await hideCapsuleAfterDelay()
    }

    // MARK: - Private: Setup Flow

    func beginOnboardingFlow() {
        guard onboardingModel == nil else { return }
        let model = OnboardingModel(downloadViewModel: modelDownloadViewModel)
        model.onCompleted = { [weak self] in
            self?.handleOnboardingCompleted()
        }
        model.onMinimize = { [weak self] in
            self?.minimizeToMiniDownload()
        }
        onboardingModel = model
        startDownloadStateObserver()
    }

    private func startDownloadStateObserver() {
        downloadStateObserverTask?.cancel()
        downloadStateObserverTask = Task { [weak self] in
            guard let self else { return }
            var wasDownloading = false
            while !Task.isCancelled {
                try? await self.clock.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                let isDownloading = self.modelDownloadViewModel.state.isActive || self.modelDownloadViewModel.state.isPaused
                if isDownloading, !wasDownloading {
                    self.startMenuBarFlash()
                } else if !isDownloading, wasDownloading {
                    self.stopMenuBarFlash()
                }
                wasDownloading = isDownloading
            }
        }
    }

    private func minimizeToMiniDownload() {
        guard !isShowingMiniDownload else { return }
        isShowingMiniDownload = true

        Task {
            await windowClient.close(WindowConfig.onboarding.id)
            await windowClient.show(.miniDownload, {
                SwiftUI.NSHostingView(rootView: MiniDownloadView(model: self.modelDownloadViewModel) { [weak self] in
                    self?.expandFromMiniDownload()
                })
            }, { [weak self] in
                self?.handleMiniDownloadClosed()
            })
        }

        startMiniDownloadRestoreObserver()
    }

    private func expandFromMiniDownload() {
        guard isShowingMiniDownload else { return }
        isShowingMiniDownload = false
        miniDownloadRestoreTask?.cancel()
        miniDownloadRestoreTask = nil

        Task {
            await windowClient.close(WindowConfig.miniDownload.id)
            showOnboardingWindow()
        }
    }

    private func handleMiniDownloadClosed() {
        isShowingMiniDownload = false
        miniDownloadRestoreTask?.cancel()
        miniDownloadRestoreTask = nil
    }

    private func startMiniDownloadRestoreObserver() {
        miniDownloadRestoreTask?.cancel()
        miniDownloadRestoreTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await self.clock.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                if self.modelDownloadViewModel.state.isDownloaded {
                    self.restoreOnboardingFromMiniDownload()
                    return
                }
            }
        }
    }

    private func restoreOnboardingFromMiniDownload() {
        guard isShowingMiniDownload else { return }
        isShowingMiniDownload = false
        miniDownloadRestoreTask?.cancel()
        miniDownloadRestoreTask = nil
        stopMenuBarFlash()

        Task {
            await windowClient.close(WindowConfig.miniDownload.id)
            showOnboardingWindow()
        }
    }

    private func startMenuBarFlash() {
        menuBarFlashTask?.cancel()
        menuBarFlashOn = true
        menuBarFlashTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await self.clock.sleep(for: .milliseconds(800))
                guard !Task.isCancelled else { return }
                self.menuBarFlashOn.toggle()
            }
        }
    }

    private func stopMenuBarFlash() {
        menuBarFlashTask?.cancel()
        menuBarFlashTask = nil
        menuBarFlashOn = true
    }

    private func handleOnboardingCompleted() {
        stopMenuBarFlash()
        downloadStateObserverTask?.cancel()
        downloadStateObserverTask = nil
        miniDownloadRestoreTask?.cancel()
        miniDownloadRestoreTask = nil
        isShowingMiniDownload = false
        selectedModelDidChange()
        $hasCompletedSetup.withLock { $0 = true }
        transientMessage = nil
        Task {
            await windowClient.close(WindowConfig.miniDownload.id)
            await windowClient.close(WindowConfig.onboarding.id)
        }
        onboardingModel = nil
        logger.info("Onboarding completed")
        consoleLog("Onboarding completed")
        Task { await warmModelTask() }
    }

    private func showOnboardingWindow() {
        if isPreviewMode { return }
        guard let onboardingModel else { return }

        Task {
            await windowClient.closeAll(WindowConfig.onboarding.id)
            await windowClient.show(.onboarding, {
                SwiftUI.NSHostingView(rootView: OnboardingView(model: onboardingModel))
            }, {})
        }
    }

    private func showSettingsWindow() {
        if isPreviewMode { return }
        let settingsViewModel = SettingsViewModel(appModel: self)
        NSApp.setActivationPolicy(.regular)
        Task {
            await windowClient.closeAll(WindowConfig.settings.id)
            await windowClient.show(.settings, {
                SwiftUI.NSHostingView(rootView: SettingsView(viewModel: settingsViewModel))
            }, {
                NSApp.setActivationPolicy(.accessory)
            })
        }
    }

    // MARK: - Private: Shortcuts & Keyboard

    func registerShortcutHandlers() {
        if isPreviewMode { return }

        switch shortcutTriggerMode {
        case .combo:
            Task { await doubleTapClient.stop() }
            KeyboardShortcuts.removeAllHandlers()
            KeyboardShortcuts.onKeyDown(for: .pushToTalk) { [weak self] in
                Task { await self?.pushToTalkKeyDown() }
            }
            KeyboardShortcuts.onKeyUp(for: .pushToTalk) { [weak self] in
                Task { await self?.pushToTalkKeyUp() }
            }

        case .doubleTap:
            KeyboardShortcuts.removeAllHandlers()
            KeyboardShortcuts.disable(.pushToTalk)
            guard doubleTapKey.isConfigured else { return }
            let key = doubleTapKey
            let interval = doubleTapInterval
            Task { [weak self] in
                await self?.doubleTapClient.start(key, interval, { [weak self] in
                    Task { @MainActor in await self?.pushToTalkKeyDown() }
                }, { [weak self] in
                    Task { @MainActor in await self?.pushToTalkKeyUp() }
                })
            }
        }
    }

    private func registerKeyboardMonitor() {
        if isPreviewMode { return }
        Task {
            await keyboardClient.start { [weak self] keyPress in
                MainActor.assumeIsolated {
                    guard let self else { return false }
                    return self.shouldConsumeKeyPress(keyPress)
                }
            }
        }
    }

    /// Decides synchronously whether to swallow the event, then dispatches async handling.
    private func shouldConsumeKeyPress(_ keyPress: KeyPress) -> Bool {
        guard case .recording = sessionState else { return false }

        if isAwaitingCancelRecordingConfirmation {
            switch keyPress {
            case .character("y"):
                Task { await handleConfirmationKeyPress(keyPress) }
                return true
            case .escape:
                // Don't capture — let it pass through to the focused app.
                return false
            default:
                return false
            }
        }

        guard keyPress == .escape else { return false }
        Task { await handleEscapeDuringRecording() }
        return true
    }

    private func handleConfirmationKeyPress(_ keyPress: KeyPress) async {
        let isCurrentlyRecording = await audioClient.isRecording()
        guard isCurrentlyRecording else { return }
        cancelRecordingFromConfirmation()
    }

    private func handleEscapeDuringRecording() async {
        let isCurrentlyRecording = await audioClient.isRecording()
        guard isCurrentlyRecording else { return }
        presentCancelRecordingConfirmation()
    }

    private static let cancelConfirmationTimeout: TimeInterval = 4

    private func presentCancelRecordingConfirmation() {
        isAwaitingCancelRecordingConfirmation = true
        cancelConfirmationTimerTask?.cancel()
        Task { await floatingCapsuleClient.showCancelConfirmation() }
        logger.info("Recording cancel confirmation shown")
        consoleLog("Recording cancel confirmation shown")

        cancelConfirmationTimerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.cancelConfirmationTimeout))
            guard !Task.isCancelled else { return }
            self?.dismissCancelRecordingConfirmation()
        }
    }

    private func dismissCancelRecordingConfirmation() {
        guard isAwaitingCancelRecordingConfirmation else { return }

        cancelConfirmationTimerTask?.cancel()
        cancelConfirmationTimerTask = nil
        isAwaitingCancelRecordingConfirmation = false
        guard case .recording = sessionState else {
            Task { await floatingCapsuleClient.hide() }
            return
        }

        Task {
            let isCurrentlyRecording = await audioClient.isRecording()
            if isCurrentlyRecording {
                await floatingCapsuleClient.showRecording()
            } else {
                await floatingCapsuleClient.hide()
            }
        }
        logger.info("Recording cancel confirmation auto-dismissed")
        consoleLog("Recording cancel confirmation auto-dismissed")
    }

    private func cancelRecordingFromConfirmation() {
        cancelConfirmationTimerTask?.cancel()
        cancelConfirmationTimerTask = nil
        Task {
            let isCurrentlyRecording = await audioClient.isRecording()
            guard isCurrentlyRecording else {
                isAwaitingCancelRecordingConfirmation = false
                await stopPlaybackDuckingIfNeeded()
                return
            }

            await audioClient.cancelRecording()

            isAwaitingCancelRecordingConfirmation = false
            pushToTalkIsActive = false
            toggleRecordingIsActive = false
            ignoreNextShortcutKeyUp = false
            currentShortcutPressStart = nil
            sessionState = .idle
            transientMessage = "Recording cancelled."
            await stopPlaybackDuckingIfNeeded()
            await floatingCapsuleClient.hide()
            logger.info("Recording canceled from keyboard confirmation")
            consoleLog("Recording canceled from keyboard confirmation")
        }
    }

    private func startPlaybackDuckingIfNeeded() async {
        guard duckSystemAudioDuringRecording, !isPlaybackDucked else { return }

        do {
            try await playbackDuckingClient.startDucking()
            isPlaybackDucked = true
            logClient.dumpDebug(
                "AppModel",
                "System audio ducking started",
                appDumpString(["targetVolumeScale": "0.5"])
            )
        } catch {
            logger.warning("System audio ducking failed: \(error.localizedDescription, privacy: .public)")
            logClient.error("AppModel", "System audio ducking failed: \(error.localizedDescription)")
        }
    }

    private func stopPlaybackDuckingIfNeeded() async {
        guard isPlaybackDucked else { return }
        isPlaybackDucked = false
        await playbackDuckingClient.stopDucking()
        logClient.dumpDebug("AppModel", "System audio ducking stopped", "")
    }

    // MARK: - Private: Permissions

    private func refreshPermissionStatus() {
        if isPreviewMode { return }
        Task { await refreshPermissionStatusAsync() }
    }

    private func refreshPermissionStatusAsync() async {
        if isPreviewMode { return }
        microphonePermissionState = await permissionsClient.microphonePermissionState()
        microphoneAuthorized = microphonePermissionState == .authorized
        accessibilityAuthorized = await permissionsClient.hasAccessibilityPermission()
    }

    private func startPermissionMonitoring() {
        permissionMonitorTask?.cancel()
        permissionMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshPermissionStatusAsync()
                try? await self.clock.sleep(for: .seconds(1))
            }
        }
    }

    // MARK: - Private: Deep Links

    private func startRecordingFromDeepLink() async {
        await refreshPermissionStatusAsync()
        logger.info(
            "Deep link start requested. setupCompleted=\(self.hasCompletedSetup, privacy: .public), microphoneAuthorized=\(self.microphoneAuthorized, privacy: .public), isProcessing=\(self.isProcessing, privacy: .public)"
        )
        consoleLog(
            "Deep link start requested. setupCompleted=\(self.hasCompletedSetup), microphoneAuthorized=\(self.microphoneAuthorized), isProcessing=\(self.isProcessing)"
        )
        let isCurrentlyRecording = await audioClient.isRecording()
        if isCurrentlyRecording || isRecordingLifecycleBusy {
            logger.info(
                "Deep link start ignored: isCurrentlyRecording=\(isCurrentlyRecording, privacy: .public), isProcessing=\(self.isProcessing, privacy: .public), isStarting=\(self.isStartingRecording, privacy: .public), isStopping=\(self.isStoppingRecording, privacy: .public)"
            )
            consoleLog(
                "Deep link start ignored: isCurrentlyRecording=\(isCurrentlyRecording), isProcessing=\(self.isProcessing), isStarting=\(self.isStartingRecording), isStopping=\(self.isStoppingRecording)"
            )
            return
        }

        guard await ensureSetupReadyForDeepLinkStart() else { return }

        await refreshPermissionStatusAsync()
        if !microphoneAuthorized {
            if Self.isRunningUnattendedE2E {
                logger.warning("Deep link start continuing without permission prompt (unattended e2e)")
                consoleLog("Deep link start continuing without permission prompt (unattended e2e)")
            } else {
                logger.info("Deep link start requesting microphone permission")
                consoleLog("Deep link start requesting microphone permission")
                await microphonePermissionButtonTapped()
                await refreshPermissionStatusAsync()
                guard microphoneAuthorized else {
                    logger.warning("Deep link start aborted: microphone permission denied")
                    consoleLog("Deep link start aborted: microphone permission denied")
                    return
                }
            }
        }

        isStartingRecording = true
        defer { isStartingRecording = false }

        do {
            logger.info("Deep link start attempting to start recording")
            consoleLog("Deep link start attempting to start recording")
            try await startRecordingWithTimeout { [weak self] level in
                guard let self else { return }
                Task { @MainActor [self, level] in
                    self.recordingLevelDidUpdate(level)
                }
            }

            isAwaitingCancelRecordingConfirmation = false
            pushToTalkIsActive = false
            toggleRecordingIsActive = true
            ignoreNextShortcutKeyUp = false
            currentShortcutPressStart = nil
            sessionState = .recording
            activeHistorySessionID = uuid()
            transientMessage = "Listening... use petal://stop to transcribe."
            await startPlaybackDuckingIfNeeded()
            logger.info("Recording started from deep link")
            consoleLog("Recording started from deep link")
            Task { await soundClient.playRecordingStarted() }
            await floatingCapsuleClient.showRecording()
        } catch {
            reportIssue(error)
            sessionState = .error(error.localizedDescription)
            lastError = error.localizedDescription
            await floatingCapsuleClient.showError("Recording failed")
            logger.error("Deep link start failed: \(error.localizedDescription, privacy: .public)")
            consoleLog("Deep link start failed: \(error.localizedDescription)")
            await hideCapsuleAfterDelay()
        }
    }

    private func startRecordingWithTimeout(
        levelHandler: @escaping @Sendable (Double) -> Void
    ) async throws {
        let startRecording = audioClient.startRecording
        let timeoutSeconds = Self.deepLinkStartTimeoutSeconds
        let timeoutInterval = DispatchTimeInterval.milliseconds(Int(timeoutSeconds * 1000))
        let timeoutLogger = Logger(subsystem: "com.optimalapps.petal", category: "AppModel")
        let continuationGate = ContinuationGate()

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let startTask = Task {
                    do {
                        try await startRecording(levelHandler)
                        timeoutLogger.debug("Deep link start task completed before timeout")
                        continuationGate.resume(continuation, with: .success(()))
                    } catch {
                        timeoutLogger.error("Deep link start task failed before timeout: \(error.localizedDescription, privacy: .public)")
                        continuationGate.resume(continuation, with: .failure(error))
                    }
                }

                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeoutInterval) {
                    let didTimeout = continuationGate.resume(
                        continuation,
                        with: .failure(DeepLinkStartError.timedOut(seconds: timeoutSeconds))
                    )
                    guard didTimeout else { return }
                    timeoutLogger.error("Deep link start timeout fired after \(timeoutSeconds, privacy: .public)s")
                    startTask.cancel()
                }
            }
            timeoutLogger.debug("Deep link start continuation completed without timeout")
        } catch {
            if let deepLinkError = error as? DeepLinkStartError, case .timedOut = deepLinkError {
                timeoutLogger.error("Deep link start timed out; canceling any pending capture session")
                let cancelRecording = audioClient.cancelRecording
                Task.detached(priority: .utility) {
                    await cancelRecording()
                }
            }
            throw error
        }
    }

    private func ensureSetupReadyForDeepLinkStart() async -> Bool {
        let intendedModelID = selectedModelID

        func reapplyIntendedModelIfNeeded(phase: String) {
            let currentModelID = selectedModelID
            guard currentModelID != intendedModelID else { return }

            logger.warning(
                "Deep link setup model drift detected. phase=\(phase, privacy: .public), intended=\(intendedModelID, privacy: .public), current=\(currentModelID, privacy: .public)"
            )
            consoleLog(
                "Deep link setup model drift detected. phase=\(phase), intended=\(intendedModelID), current=\(currentModelID)"
            )

            modelDownloadViewModel.$selectedModelID.withLock { $0 = intendedModelID }
            modelDownloadViewModel.selectedModelChanged()
        }

        reapplyIntendedModelIfNeeded(phase: "bootstrap")
        modelDownloadViewModel.selectedModelChanged()

        guard let selectedModelOption = ModelOption(rawValue: intendedModelID) else {
            logger.error("Deep link start failed: selected model is unavailable")
            consoleLog("Deep link start failed: selected model is unavailable")
            return false
        }

        logger.info(
            "Deep link setup bootstrap begin. model=\(selectedModelOption.rawValue, privacy: .public), requiresDownload=\(selectedModelOption.requiresDownload, privacy: .public), isDownloaded=\(self.isSelectedModelDownloaded, privacy: .public), hasCompletedSetup=\(self.hasCompletedSetup, privacy: .public)"
        )
        consoleLog(
            "Deep link setup bootstrap begin. model=\(selectedModelOption.rawValue), requiresDownload=\(selectedModelOption.requiresDownload), isDownloaded=\(self.isSelectedModelDownloaded), hasCompletedSetup=\(self.hasCompletedSetup)"
        )

        if selectedModelOption.requiresDownload, !isSelectedModelDownloaded {
            transientMessage = "Preparing \(selectedModelOption.displayName)…"
            let maxAttempts = 3
            var didDownload = false

            for attempt in 1...maxAttempts {
                reapplyIntendedModelIfNeeded(phase: "download-attempt-\(attempt)-preflight")
                logger.info(
                    "Deep link setup downloading model: \(selectedModelOption.rawValue, privacy: .public), attempt=\(attempt, privacy: .public)"
                )
                consoleLog("Deep link setup downloading model: \(selectedModelOption.rawValue), attempt=\(attempt)")

                await modelDownloadViewModel.downloadModel()
                reapplyIntendedModelIfNeeded(phase: "download-attempt-\(attempt)-completion")

                transientMessage = modelDownloadViewModel.transientMessage
                lastError = modelDownloadViewModel.lastError

                let stateDownloaded = modelDownloadViewModel.state.isDownloaded
                let cacheCheckDownloaded = isSelectedModelDownloaded
                let directoryFound = modelDownloadViewModel.modelDirectoryURL != nil
                let modelReady = cacheCheckDownloaded || (stateDownloaded && directoryFound)

                if modelReady {
                    didDownload = true
                    logger.info(
                        "Deep link setup model download complete: \(selectedModelOption.rawValue, privacy: .public), stateDownloaded=\(stateDownloaded, privacy: .public), cacheCheckDownloaded=\(cacheCheckDownloaded, privacy: .public), directoryFound=\(directoryFound, privacy: .public)"
                    )
                    consoleLog(
                        "Deep link setup model download complete: \(selectedModelOption.rawValue), stateDownloaded=\(stateDownloaded), cacheCheckDownloaded=\(cacheCheckDownloaded), directoryFound=\(directoryFound)"
                    )
                    break
                }

                let reason = modelDownloadViewModel.lastError ?? "Model download did not complete."
                logger.error(
                    "Deep link setup download attempt failed. model=\(selectedModelOption.rawValue, privacy: .public), attempt=\(attempt, privacy: .public), state=\(String(describing: self.modelDownloadViewModel.state), privacy: .public), cacheCheckDownloaded=\(cacheCheckDownloaded, privacy: .public), directoryFound=\(directoryFound, privacy: .public), reason=\(reason, privacy: .public)"
                )
                consoleLog(
                    "Deep link setup download attempt failed. model=\(selectedModelOption.rawValue), attempt=\(attempt), state=\(String(describing: self.modelDownloadViewModel.state)), cacheCheckDownloaded=\(cacheCheckDownloaded), directoryFound=\(directoryFound), reason=\(reason)"
                )

                if attempt < maxAttempts {
                    try? await clock.sleep(for: .seconds(2))
                }
            }

            guard didDownload else {
                let reason = modelDownloadViewModel.lastError ?? "Model download did not complete."
                logger.error("Deep link setup download failed: \(reason, privacy: .public)")
                consoleLog("Deep link setup download failed: \(reason)")
                return false
            }
        }

        if !hasCompletedSetup || onboardingModel != nil {
            stopMenuBarFlash()
            downloadStateObserverTask?.cancel()
            downloadStateObserverTask = nil
            miniDownloadRestoreTask?.cancel()
            miniDownloadRestoreTask = nil
            isShowingMiniDownload = false
            onboardingModel = nil
            $hasCompletedSetup.withLock { $0 = true }
            await windowClient.close(WindowConfig.miniDownload.id)
            await windowClient.close(WindowConfig.onboarding.id)
            logger.info("Deep link setup marked complete")
            consoleLog("Deep link setup marked complete")
        }

        reapplyIntendedModelIfNeeded(phase: "warmup-preflight")
        await warmModelTask()
        reapplyIntendedModelIfNeeded(phase: "warmup-complete")
        transientMessage = nil
        return true
    }

    private func stopRecordingFromDeepLink() async {
        let isCurrentlyRecording = await audioClient.isRecording()
        logger.info("Deep link stop requested. isCurrentlyRecording=\(isCurrentlyRecording, privacy: .public)")
        consoleLog("Deep link stop requested. isCurrentlyRecording=\(isCurrentlyRecording)")
        guard isCurrentlyRecording else {
            logger.info("Deep link stop ignored: no active recording")
            consoleLog("Deep link stop ignored: no active recording")
            return
        }
        logger.info("Stopping recording from deep link")
        consoleLog("Stopping recording from deep link")
        await stopRecordingAndTranscribe()
    }

    private func toggleRecordingFromDeepLink() async {
        let isCurrentlyRecording = await audioClient.isRecording()
        logger.info("Deep link toggle requested. isCurrentlyRecording=\(isCurrentlyRecording, privacy: .public)")
        consoleLog("Deep link toggle requested. isCurrentlyRecording=\(isCurrentlyRecording)")
        if isCurrentlyRecording {
            await stopRecordingFromDeepLink()
        } else {
            await startRecordingFromDeepLink()
        }
    }

    // MARK: - Private: Helpers

    private var isRecordingLifecycleBusy: Bool {
        isStartingRecording || isStoppingRecording || isTranscribingDroppedFile || isProcessing
    }

    private func recordingLevelDidUpdate(_ level: Double) {
        guard case .recording = sessionState else { return }
        currentLevel = level
        Task { await floatingCapsuleClient.updateLevel(level) }
    }

    private func warmModelTask() async {
        if isPreviewMode { return }
        guard let selectedModelOption else { return }
        logger.info("Warming model: \(selectedModelOption.rawValue, privacy: .public)")
        consoleLog("Warming model: \(selectedModelOption.rawValue)")

        do {
            try await transcriptionClient.prepareModelIfNeeded(selectedModelOption)
            logger.info("Model warmup complete: \(selectedModelOption.rawValue, privacy: .public)")
            consoleLog("Model warmup complete: \(selectedModelOption.rawValue)")
        } catch {
            reportIssue(error)
            transientMessage = "Model will load on first transcription."
            logger.error("Model warmup failed: \(error.localizedDescription, privacy: .public)")
            consoleLog("Model warmup failed: \(error.localizedDescription)")
        }
    }

    private func showCopiedThenAccessibilityPrompt() async {
        await floatingCapsuleClient.showCopiedToClipboard()
        try? await clock.sleep(for: .seconds(3))
        await floatingCapsuleClient.showAccessibilityPrompt { [permissionsClient] in
            Task {
                await permissionsClient.promptForAccessibilityPermission()
                await permissionsClient.openAccessibilityPrivacySettings()
            }
        }
        // Poll for up to 10s — show success immediately if granted
        for _ in 0..<20 {
            try? await clock.sleep(for: .milliseconds(500))
            if await permissionsClient.hasAccessibilityPermission() {
                await floatingCapsuleClient.showAccessibilityEnabled()
                accessibilityAuthorized = true
                try? await clock.sleep(for: .seconds(2))
                break
            }
        }
        isAwaitingCancelRecordingConfirmation = false
        stopTranscriptionProgressTracking()
        await floatingCapsuleClient.hide()
    }

    private func hideCapsuleAfterDelay() async {
        try? await clock.sleep(for: .milliseconds(300))
        isAwaitingCancelRecordingConfirmation = false
        stopTranscriptionProgressTracking()
        await floatingCapsuleClient.hide()

        if case .error = sessionState {
            sessionState = .idle
        }
    }

    private var isProcessing: Bool {
        if case .processing = sessionState { return true }
        return false
    }

    private func normalizedTranscriptionMode(_ mode: TranscriptionMode) -> TranscriptionMode {
        guard let selectedModelOption else { return mode }
        if selectedModelOption.supportsTranscriptionMode(mode) { return mode }
        // Allow smart mode when Apple Intelligence can post-process
        if mode == .smart, appleIntelligenceEnabled, foundationModelClient.isAvailable() { return mode }
        return .verbatim
    }

    private func autoSpeedRate(for audioDuration: Double) -> Double? {
        switch audioDuration {
        case ..<45: return nil
        case 45..<90: return 1.1
        case 90..<180: return 1.2
        default: return 1.25
        }
    }

    private func postPasteFallbackNotification() async {
        await postCopiedToClipboardNotification(body: "Transcript copied to clipboard. Press Command-V to paste.")
    }

    private func postCopiedToClipboardNotification(body: String) async {
        if isPreviewMode { return }
        let center = UNUserNotificationCenter.current()

        let settings = await center.notificationSettings()

        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }

        let content = UNMutableNotificationContent()
        content.title = "Petal"
        content.body = body

        let request = UNNotificationRequest(
            identifier: uuid().uuidString,
            content: content,
            trigger: nil
        )

        try? await center.add(request)
    }

    private func copyTranscriptToClipboard(_ transcript: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(transcript, forType: .string)
    }

    private func consoleLog(_ message: String) {
        logClient.debug("AppModel", message)
    }

    private func formatElapsedSeconds(_ seconds: Double) -> String {
        String(format: "%.3fs", seconds)
    }

    private func appAudioFileSizeBytes(_ url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values?.fileSize else { return nil }
        return Int64(size)
    }

    private func normalizeDroppedAudioFileForTranscription(_ url: URL) async throws -> URL {
        try await Task.detached(priority: .utility) {
            let input = try AVAudioFile(forReading: url)
            let outputURL = FileManager.default.temporaryDirectory
                .appending(path: "petal-import-\(UUID().uuidString).wav")
            let output = try AVAudioFile(
                forWriting: outputURL,
                settings: input.processingFormat.settings
            )
            let frameCapacity = AVAudioFrameCount(min(input.processingFormat.sampleRate, 48_000))
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: input.processingFormat,
                frameCapacity: max(frameCapacity, 1)
            ) else {
                throw AppTranscriptionError.audioImportFailed
            }

            while input.framePosition < input.length {
                try input.read(into: buffer)
                guard buffer.frameLength > 0 else { break }
                try output.write(from: buffer)
            }

            return outputURL
        }.value
    }

    private func startTranscriptionProgressTracking(audioDuration: Double) {
        stopTranscriptionProgressTracking()
        let expectedDuration = estimatedTranscriptionDuration(for: audioDuration)
        let start = now

        transcriptionProgressTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                let elapsed = now.timeIntervalSince(start)
                let normalized = max(elapsed / expectedDuration, 0)
                let progress: Double
                if normalized <= 1 {
                    // Move faster in the early/mid phase so progress does not feel stalled.
                    progress = min(pow(normalized, 0.72) * 0.94, 0.94)
                } else {
                    // Keep advancing past expected duration instead of freezing in the high 90s.
                    let tail = min((normalized - 1) / 2.0, 1)
                    progress = 0.94 + (0.995 - 0.94) * tail
                }
                await self.floatingCapsuleClient.updateTranscriptionProgress(progress)

                try? await self.clock.sleep(for: .milliseconds(120))
            }
        }
    }

    private func stopTranscriptionProgressTracking(finalProgress: Double? = nil) {
        transcriptionProgressTask?.cancel()
        transcriptionProgressTask = nil

        if let finalProgress {
            Task { await floatingCapsuleClient.updateTranscriptionProgress(finalProgress) }
        }
    }

    private func estimatedTranscriptionDuration(for audioDuration: Double) -> Double {
        guard audioDuration > 0 else { return 5 }
        let estimate = audioDuration / max(estimatedTranscriptionRTF, 0.2)
        return max(2, estimate)
    }

    private func defaultTranscriptionRTF(for model: ModelOption?) -> Double {
        guard let model else { return 2.2 }

        switch model {
        case .qwen3ASR06B4bit:
            return 2.2
        case .parakeetTDT06BV3:
            return 1.8
        case .parakeetTDT06BV2:
            return 2.0
        case .parakeetTDTCTC110M:
            return 2.5
        case .whisperLargeV3Turbo:
            return 0.85
        case .whisperTiny:
            return 2.8
        case .mini3b:
            return 0.8
        case .mini3b8bit:
            return 1.1
        case .appleSpeech:
            return 2.6
        }
    }

    private func updateTranscriptionSpeedEstimate(audioDuration: Double, elapsed: Double) {
        guard audioDuration > 0, elapsed > 0 else { return }
        let latestRTF = audioDuration / elapsed
        let alpha = 0.25
        estimatedTranscriptionRTF = (1 - alpha) * estimatedTranscriptionRTF + alpha * latestRTF
    }

    private func appendTranscriptHistory(
        transcript: String,
        modelID: String,
        mode: String,
        audioDuration: Double,
        transcriptionElapsed: Double,
        pasteResult: PasteResult,
        audioRelativePath: String?,
        transcriptRelativePath: String?,
        sessionID: UUID
    ) {
        let entry = historyClient.appendEntry(
            AppendEntryRequest(
                currentDays: transcriptHistoryDays,
                transcript: transcript,
                modelID: modelID,
                mode: mode,
                audioDuration: audioDuration,
                transcriptionElapsed: transcriptionElapsed,
                pasteResult: pasteResult.rawValue,
                audioRelativePath: audioRelativePath,
                transcriptRelativePath: transcriptRelativePath,
                retentionMode: historyRetentionMode,
                timestamp: now,
                sessionID: sessionID
            )
        )
        $transcriptHistoryDays.withLock { $0 = entry }
    }

    private func persistHistoryArtifacts(
        audioURL: URL,
        transcript: String,
        timestamp: Date,
        mode: String,
        modelID: String,
        persistAudio: Bool = true
    ) async -> PersistedArtifacts? {
        await historyClient.persistArtifacts(
            PersistArtifactsRequest(
                audioURL: audioURL,
                transcript: transcript,
                timestamp: timestamp,
                mode: mode,
                modelID: modelID,
                retentionMode: historyRetentionMode,
                compressAudio: compressHistoryAudio,
                persistAudio: persistAudio
            )
        )
    }

    private func formattedHistoryEntry(_ entry: TranscriptHistoryEntry) -> String {
        historyClient.transcriptText(entry.preferredTranscriptRelativePath) ?? ""
    }

    deinit {
        transcriptionProgressTask?.cancel()
        permissionMonitorTask?.cancel()
        miniDownloadRestoreTask?.cancel()
        menuBarFlashTask?.cancel()
        downloadStateObserverTask?.cancel()
    }
}

private enum AppTranscriptionError: LocalizedError {
    case pipelineUnavailable
    case audioImportFailed

    var errorDescription: String? {
        switch self {
        case .pipelineUnavailable:
            return "Transcription pipeline is not available."
        case .audioImportFailed:
            return "Could not prepare this audio file for transcription."
        }
    }
}

private final class ContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    @discardableResult
    func resume(
        _ continuation: CheckedContinuation<Void, Error>,
        with result: Result<Void, Error>
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return false }
        didResume = true
        continuation.resume(with: result)
        return true
    }
}

private enum DeepLinkStartError: LocalizedError {
    case timedOut(seconds: Double)

    var errorDescription: String? {
        switch self {
        case let .timedOut(seconds):
            let wholeSeconds = Int(seconds.rounded())
            return "Timed out after \(wholeSeconds)s waiting for audio capture to start."
        }
    }
}

extension AppModel {
    static func makePreview(_ configure: (AppModel) -> Void = { _ in }) -> AppModel {
        let model = AppModel(isPreviewMode: true)
        model.$hasCompletedSetup.withLock { $0 = true }
        model.selectedModelID = ModelOption.defaultOption.rawValue
        model.sessionState = .idle
        model.lastError = nil
        model.transientMessage = nil
        model.$transcriptHistoryDays.withLock { $0 = [] }
        model.microphonePermissionState = .authorized
        model.microphoneAuthorized = true
        model.accessibilityAuthorized = true
        configure(model)
        return model
    }
}
