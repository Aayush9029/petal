import Foundation
import KeyboardClient
import KeyboardShortcuts
import Shared
import UI

extension AppModel {
    struct RecordingSession {
        let id: UUID
        let model: ModelOption
    }

    enum RecordingShortcut {
        case idle
        case pressed(Date)
        case latched
    }

    enum RecordingEnd: Equatable {
        case transcribe
        case send
        case cancel
    }

    enum RecordingTransition: Equatable {
        case starting(RecordingEnd?)
        case ending
    }

    private enum RecordingTrigger {
        case shortcut
        case deepLink
    }

    var isRecordingLifecycleBusy: Bool {
        recordingTransition != nil || isTranscribingDroppedFile || isProcessing
    }

    private var isStartingRecording: Bool {
        if case .starting = recordingTransition { return true }
        return false
    }

    func pushToTalkKeyDown() async {
        if cancelConfirmationTimerTask != nil {
            dismissCancelRecordingConfirmation()
        }
        guard hasCompletedSetup else {
            menuTransientMessage = "Finish setup to record"
            beginOnboardingFlow()
            showOnboardingWindow()
            return
        }
        switch recordingShortcut {
        case .idle:
            await startRecording(.shortcut)
        case .latched:
            await endRecording(.transcribe)
        case .pressed:
            break
        }
    }

    func pushToTalkKeyUp() async {
        guard cancelConfirmationTimerTask == nil, case let .pressed(start) = recordingShortcut else { return }
        if now.timeIntervalSince(start) < pushToTalkThreshold.seconds {
            recordingShortcut = .latched
            menuTransientMessage = nil
        } else {
            await endRecording(.transcribe)
        }
    }

    func startRecordingFromDeepLink() async {
        await startRecording(.deepLink)
    }

    func stopRecordingFromDeepLink() async {
        guard sessionState == .recording || isStartingRecording else {
            logClient.debug("AppModel", "Deep link stop ignored: no active recording")
            return
        }
        logClient.debug("AppModel", "Stopping recording from deep link")
        await endRecording(.transcribe)
    }

    func toggleRecordingFromDeepLink() async {
        if sessionState == .recording || isStartingRecording {
            await stopRecordingFromDeepLink()
        } else {
            await startRecordingFromDeepLink()
        }
    }

    private func startRecording(_ trigger: RecordingTrigger) async {
        guard !isRecordingLifecycleBusy, sessionState != .recording else {
            if trigger == .deepLink {
                logClient.debug("AppModel", "Deep link start ignored: recording lifecycle busy")
            }
            return
        }

        recordingTransition = .starting(nil)
        recordingShortcut = trigger == .shortcut ? .pressed(now) : .latched
        cancelAccessibilityFollowUp()
        await prepareAndStartRecording(trigger, model: selectedModelOption)
        guard case let .starting(end) = recordingTransition else { return }
        recordingTransition = nil
        guard sessionState == .recording else {
            recordingShortcut = .idle
            return
        }
        if let end { await endRecording(end) }
    }

    private func prepareAndStartRecording(_ trigger: RecordingTrigger, model: ModelOption?) async {
        do {
            guard let model else { throw AppTranscriptionError.pipelineUnavailable }
            if trigger == .deepLink {
                guard await prepareDeepLinkModel(model) else { return }
                await refreshPermissionStatusAsync()
            }

            if !microphoneAuthorized, !(trigger == .deepLink && Self.isRunningUnattendedE2E) {
                await microphonePermissionButtonTapped()
                guard microphoneAuthorized else {
                    if trigger == .deepLink {
                        logClient.debug("AppModel", "Deep link start aborted: microphone permission denied")
                    } else {
                        sessionState = .error("Microphone permission denied")
                        menuTransientMessage = "Turn on microphone access"
                        await floatingCapsuleClient.showError("Microphone denied")
                        await hideCapsuleAfterDelay()
                    }
                    return
                }
            }

            guard !Task.isCancelled else { return }
            let session = RecordingSession(id: uuid(), model: model)
            recordingSession = session
            if trigger == .deepLink {
                try await startCaptureWithTimeout(session)
                menuTransientMessage = nil
            } else {
                try await startAudioCapture(session)
            }
            sessionState = .recording
            prepareCleanupModelIfNeeded()
            await startPlaybackDuckingIfNeeded()
            let message = trigger == .deepLink ? "Recording started from deep link" : "Recording started"
            logClient.debug("AppModel", message)
            Task { await soundClient.play(.recordingStarted) }
            await showRecordingCapsule()
        } catch {
            recordingSession = nil
            if error is CancellationError {
                sessionState = .idle
            } else {
                sessionState = .error(error.localizedDescription)
                let prefix = trigger == .deepLink ? "Deep link start failed" : "Recording failed to start"
                logClient.debug("AppModel", "\(prefix): \(error.localizedDescription)")
                await floatingCapsuleClient.showError("Recording failed")
            }
            await audioClient.cancelRecording()
            await cancelStreamingTranscription()
            if case .error = sessionState { await hideCapsuleAfterDelay() }
        }
    }

    private func prepareDeepLinkModel(_ model: ModelOption) async -> Bool {
        if !modelDownloadViewModel.isModelDownloaded(model) {
            menuTransientMessage = "Preparing \(model.displayName)…"
            await modelDownloadViewModel.downloadModel(model)
            menuTransientMessage = nil
            guard modelDownloadViewModel.isModelDownloaded(model) else {
                let reason = modelDownloadViewModel.lastError ?? "Model download did not complete."
                logClient.error("AppModel", "Deep link setup download failed: \(reason)")
                return false
            }
        }

        if !hasCompletedSetup || onboardingModel != nil {
            await finishOnboarding()
        }

        await warmModelTask(model)
        menuTransientMessage = nil
        return true
    }

    private func startAudioCapture(_ session: RecordingSession) async throws {
        try Task.checkCancellation()
        let levelHandler: @Sendable (Double) -> Void = { [weak self] level in
            Task { @MainActor [weak self] in
                guard let self, recordingSession?.id == session.id, sessionState == .recording, recordingTransition != .ending else { return }
                currentLevel = level
                await floatingCapsuleClient.updateLevel(level)
            }
        }
        if session.model.supportsStreamingTranscription {
            let audio = try await audioClient.startStreamingRecording(levelHandler)
            try Task.checkCancellation()
            let client = transcriptionClient
            streamingTask = Task { [weak self] in
                try await client.transcribeStream(audio, session.model) { [weak self] text in
                    await self?.streamingTranscriptDidUpdate(text, sessionID: session.id)
                }
            }
        } else {
            try await audioClient.startRecording(levelHandler)
            try Task.checkCancellation()
        }
    }

    private func startCaptureWithTimeout(_ session: RecordingSession) async throws {
        // Core Audio startup can ignore cancellation. A task group would wait for it past the deadline.
        let (result, completion) = AsyncThrowingStream<Void, any Error>.makeStream()
        let capture = Task {
            do {
                try await startAudioCapture(session)
                completion.finish()
            } catch {
                completion.finish(throwing: error)
            }
        }
        let deadline = Task {
            try await clock.sleep(for: .seconds(Self.deepLinkStartTimeoutSeconds))
            completion.finish(throwing: DeepLinkStartError())
        }
        defer {
            deadline.cancel()
            capture.cancel()
        }
        for try await _ in result {}
        try Task.checkCancellation()
    }

    private func streamingTranscriptDidUpdate(_ text: String, sessionID: UUID) async {
        guard recordingSession?.id == sessionID, sessionState == .recording, recordingTransition != .ending, !Task.isCancelled else { return }
        await floatingCapsuleClient.updateLiveTranscript(showLiveTranscript ? text : "")
    }

    func cancelStreamingTranscription() async {
        let task = streamingTask
        streamingTask = nil
        task?.cancel()
        _ = await task?.result
    }

    private func endRecording(_ action: RecordingEnd) async {
        recordingShortcut = .idle
        if case .starting(nil) = recordingTransition {
            recordingTransition = .starting(action)
            return
        }
        guard recordingTransition == nil, sessionState == .recording, let session = recordingSession else { return }
        recordingTransition = .ending
        defer {
            recordingSession = nil
            recordingTransition = nil
        }
        clearCancelRecordingConfirmation()
        sendNowChordStart = nil
        switch action {
        case .transcribe, .send:
            await stopRecordingAndTranscribe(session, sendsAfterPaste: action == .send)
        case .cancel:
            await audioClient.cancelRecording()
            await cancelStreamingTranscription()
            sessionState = .idle
            menuTransientMessage = nil
            await playbackDuckingClient.stopDucking()
            await floatingCapsuleClient.hide()
            logClient.debug("AppModel", "Recording canceled")
        }
    }

    func registerShortcutHandlers() {
        guard !isPreviewMode else { return }
        KeyboardShortcuts.removeAllHandlers()
        let keyDown: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in await self?.pushToTalkKeyDown() }
        }
        let keyUp: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in await self?.pushToTalkKeyUp() }
        }

        switch shortcutTriggerMode {
        case .combo:
            doubleTapClient.stop()
            KeyboardShortcuts.onKeyDown(for: .pushToTalk, action: keyDown)
            KeyboardShortcuts.onKeyUp(for: .pushToTalk, action: keyUp)
        case .doubleTap:
            KeyboardShortcuts.disable(.pushToTalk)
            let key = doubleTapKey
            let interval = doubleTapInterval
            if key.isConfigured {
                doubleTapClient.start(key, interval, keyDown, keyUp)
            } else {
                doubleTapClient.stop()
            }
        }
    }

    // KeyboardShortcuts streams survive removeAllHandlers() when the recording binding changes.
    func listenForPasteLastTranscriptionShortcut() {
        guard !isPreviewMode else { return }
        pasteLastTranscriptionTask = Task { [weak self] in
            for await _ in KeyboardShortcuts.events(.keyDown, for: .pasteLastTranscription) {
                await self?.pasteLastTranscriptionKeyDown()
            }
        }
    }

    private func pasteLastTranscriptionKeyDown() async {
        guard sessionState != .recording, !isRecordingLifecycleBusy, let lastTranscript else { return }
        if await pasteClient.paste(lastTranscript, restoreClipboardAfterPaste) == .copiedOnly {
            await postPasteFallbackNotification()
        }
    }

    func registerKeyboardMonitor() {
        guard !isPreviewMode else { return }
        keyboardClient.start { [weak self] keyPress in
            self?.shouldConsumeKeyPress(keyPress) ?? false
        }
    }

    private func shouldConsumeKeyPress(_ keyPress: KeyPress) -> Bool {
        guard sessionState == .recording, recordingTransition != .ending else { return false }
        if cancelConfirmationTimerTask != nil {
            guard keyPress == .character("y") else { return false }
            recordingEndHandler(.cancel)()
            return true
        }

        let chordStart = sendNowChordStart
        sendNowChordStart = nil
        switch keyPress {
        case .control("x"):
            sendNowChordStart = now
        case .control("s") where chordStart.map({ now.timeIntervalSince($0) <= 1.5 }) == true:
            recordingEndHandler(.send)()
        case .escape:
            presentCancelRecordingConfirmation()
        default:
            return false
        }
        return true
    }

    private func presentCancelRecordingConfirmation() {
        cancelConfirmationTimerTask?.cancel()
        cancelConfirmationTimerTask = Task { [weak self, clock] in
            guard !Task.isCancelled else { return }
            await self?.floatingCapsuleClient.showCancelConfirmation()
            do {
                try await clock.sleep(for: FloatingCapsuleState.cancelConfirmationTimeout)
            } catch {
                return
            }
            self?.dismissCancelRecordingConfirmation()
        }
    }

    private func clearCancelRecordingConfirmation() {
        cancelConfirmationTimerTask?.cancel()
        cancelConfirmationTimerTask = nil
    }

    private func dismissCancelRecordingConfirmation() {
        clearCancelRecordingConfirmation()
        guard sessionState == .recording, recordingTransition != .ending else { return }
        let sessionID = recordingSession?.id
        Task {
            guard sessionState == .recording, recordingTransition != .ending, recordingSession?.id == sessionID else { return }
            await showRecordingCapsule()
        }
    }

    private func recordingEndHandler(_ action: RecordingEnd) -> @Sendable () -> Void {
        let sessionID = recordingSession?.id
        return { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, sessionID != nil, recordingSession?.id == sessionID else { return }
                await endRecording(action)
            }
        }
    }

    private func showRecordingCapsule() async {
        await floatingCapsuleClient.showRecording(recordingEndHandler(.transcribe), recordingEndHandler(.cancel))
    }

    private func startPlaybackDuckingIfNeeded() async {
        guard duckSystemAudioDuringRecording else { return }
        do {
            try await playbackDuckingClient.startDucking()
        } catch {
            logClient.error("AppModel", "System audio ducking failed: \(error.localizedDescription)")
        }
    }
}

private struct DeepLinkStartError: LocalizedError {
    var errorDescription: String? {
        "Timed out after \(Int(AppModel.deepLinkStartTimeoutSeconds))s waiting for audio capture to start."
    }
}
