import Foundation
import HistoryClient
import LogClient
import PasteClient
import Shared
import TranscriptionClient

extension AppModel {
    public func audioFilesDropped(_ urls: [URL]) async {
        guard case let .accepted(url) = AudioFileDropValidator.validate(urls) else {
            menuTransientMessage = nil
            return
        }
        await transcribeFile(url, origin: .dropped)
    }

    func reprocessTranscriptHistoryButtonTapped(_ entryID: UUID, cleansUp: Bool) async {
        guard let entry = transcriptHistoryDays.lazy.compactMap({ $0.entries[id: entryID] }).first,
              let audioURL = historyClient.historyAudioURL(entry.audioRelativePath)
        else {
            menuTransientMessage = nil
            return
        }
        await transcribeFile(audioURL, origin: .history(entry, cleansUp: cleansUp))
    }

    func recoverUnfinishedRecordings() async {
        for audioURL in await audioClient.unfinishedRecordings() {
            logClient.info("AppModel", "Recovering unfinished recording \(audioURL.lastPathComponent)")
            guard await transcribeFile(audioURL, origin: .recovered) else { return }
            try? FileManager.default.removeItem(at: audioURL)
        }
    }

    @discardableResult
    private func transcribeFile(_ audioURL: URL, origin: AudioFileOrigin) async -> Bool {
        guard hasCompletedSetup else {
            if !origin.isRecovered {
                menuTransientMessage = "Finish setup to transcribe"
                changeModelButtonTapped()
            }
            return false
        }
        guard !isRecordingLifecycleBusy, sessionState != .recording else { return false }

        isTranscribingDroppedFile = true
        defer { isTranscribingDroppedFile = false }
        guard !(await audioClient.isRecording()) else { return false }

        let override = origin.isRecovered ? nil : fileTranscriptionModelOverride
        guard let model = override ?? selectedModelOption else {
            sessionState = .error(AppTranscriptionError.pipelineUnavailable.localizedDescription)
            return false
        }
        defer {
            if override != nil { scheduleWarmup() }
        }

        let accessed = audioURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { audioURL.stopAccessingSecurityScopedResource() }
        }

        menuTransientMessage = nil
        await showProcessingStage(.transcribing)
        let sessionID = origin.historyEntry?.id ?? uuid()
        let started = now
        let normalizedURL = FileManager.default.temporaryDirectory
            .appending(path: "petal-import-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: normalizedURL) }

        do {
            try await transcriptionClient.importAudio(audioURL, normalizedURL)
            let duration = transcriptionClient.audioDurationSeconds(normalizedURL)
            let mode = normalizedTranscriptionMode(transcriptionMode, model: model)
            let transcript = try await recognize(normalizedURL, model: model, duration: duration)
            let elapsed = now.timeIntervalSince(started)
            let route = cleanupRoutes.route(for: origin.historyEntry?.app)
            let cleanup = origin.requestsCleanup ? readyCleanupModel(for: route) : nil
            let text = await refine(transcript, using: cleanup, prompt: route?.prompt, sessionID: sessionID)

            let hasSpeech = !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let history = HistoryRecording(
                id: sessionID, audioURL: audioURL, modelID: model.rawValue,
                timestamp: origin.historyEntry?.timestamp ?? started,
                duration: duration, elapsed: elapsed, app: origin.historyEntry?.app
            )
            await saveHistory(
                history, mode: mode.rawValue, text: text,
                original: text == transcript ? nil : transcript,
                pasteResult: hasSpeech ? .copiedOnly : .skipped,
                replacing: origin.historyEntry
            )

            if hasSpeech {
                await soundClient.play(.transcriptionCompleted)
                pasteClient.copy(text)
                await notificationClient.post(origin.isRecovered
                    ? "Petal recovered your last recording and copied it to the clipboard."
                    : "Copied to clipboard")
                menuTransientMessage = nil
                await floatingCapsuleClient.showCopiedToClipboard()
            } else {
                await noSpeechDetected()
            }
            sessionState = .idle
            await hideCapsuleAfterDelay()
            return true
        } catch {
            await transcriptionFailed(error, sessionID: sessionID)
            return true
        }
    }

    func stopRecordingAndTranscribe(_ session: RecordingSession, sendsAfterPaste: Bool) async {
        guard await audioClient.isRecording() else {
            await cancelStreamingTranscription()
            sessionState = .idle
            await playbackDuckingClient.stopDucking()
            await floatingCapsuleClient.hide()
            return
        }

        let sessionID = session.id
        let started = now
        let model = session.model
        await showProcessingStage(.transcribing)
        var ownedRecording: URL?
        defer {
            if let ownedRecording { try? FileManager.default.removeItem(at: ownedRecording) }
        }
        do {
            let audioURL = try await audioClient.stopRecording()
            ownedRecording = audioURL
            let readFocusedApp = systemContextClient.focusedApp
            async let focusedApp = readFocusedApp()
            await playbackDuckingClient.stopDucking()

            let duration = transcriptionClient.audioDurationSeconds(audioURL)
            let mode = normalizedTranscriptionMode(transcriptionMode, model: model)
            if transcriptionMode != mode { $transcriptionMode.withLock { $0 = mode } }
            let stream = streamingTask
            streamingTask = nil
            let transcriptionStart = now
            let transcript = try await recognize(audioURL, model: model, duration: duration, stream: stream)
            let elapsed = now.timeIntervalSince(transcriptionStart)
            let app = await focusedApp
            let route = cleanupRoutes.route(for: app)
            let allowsCleanup = (route?.action ?? cleanupFallbackAction) == .cleanUp
                && cleanupMinimumWords.allowsCleanup(of: transcript)
            let cleanup = allowsCleanup ? readyCleanupModel(for: route) : nil

            if cleanup == .cloud || cleanup == .appleIntelligence,
               !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await soundClient.play(.refineStarted)
            }
            let text = await refine(transcript, using: cleanup, prompt: route?.prompt, sessionID: sessionID)
            let history = HistoryRecording(
                id: sessionID, audioURL: audioURL, modelID: model.rawValue, timestamp: transcriptionStart,
                duration: duration, elapsed: elapsed, app: app
            )

            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await noSpeechDetected()
                if !(await saveHistory(history, mode: mode.rawValue, text: text, pasteResult: .skipped)) {
                    ownedRecording = nil
                }
            } else {
                await soundClient.play(.transcriptionCompleted)
                lastTranscript = text
                let result = await pasteClient.paste(text, restoreClipboardAfterPaste)
                if sendsAfterPaste, result == .pasted {
                    // Web views can dispatch the paste after the synthetic Command-V returns.
                    try? await clock.sleep(for: .milliseconds(330))
                    await pasteClient.pressReturn()
                }
                logClient.debug("AppModel", "Transcription completed. characters=\(text.count), pasteResult=\(result.rawValue)")
                ownedRecording = nil
                // The encoder owns the capture file after the capsule closes.
                Task {
                    await saveHistory(
                        history, mode: mode.rawValue, text: text,
                        original: text == transcript ? nil : transcript, pasteResult: result
                    )
                    try? FileManager.default.removeItem(at: audioURL)
                }

                switch result {
                case .pasted:
                    menuTransientMessage = nil
                    sessionState = .idle
                    await floatingCapsuleClient.hide()
                    return
                case .copiedOnly:
                    menuTransientMessage = "Accessibility access is needed to paste. Turn it on in System Settings, then try again."
                    await postPasteFallbackNotification()
                    sessionState = .idle
                    scheduleCopiedThenAccessibilityPrompt()
                    return
                case .skipped:
                    break
                }
            }
            sessionState = .idle
            await hideCapsuleAfterDelay()
        } catch {
            await cancelStreamingTranscription()
            await audioClient.cancelRecording()
            await playbackDuckingClient.stopDucking()
            if let audioURL = ownedRecording {
                let history = HistoryRecording(
                    id: sessionID, audioURL: audioURL, modelID: model.rawValue,
                    timestamp: started, duration: transcriptionClient.audioDurationSeconds(audioURL),
                    elapsed: now.timeIntervalSince(started), app: nil
                )
                if !(await saveHistory(history, mode: "failed", text: "", pasteResult: .skipped)) {
                    ownedRecording = nil
                }
            }
            await transcriptionFailed(error, sessionID: sessionID)
        }
    }

    private func recognize(
        _ audioURL: URL,
        model: ModelOption,
        duration: TimeInterval,
        stream: Task<String, any Error>? = nil
    ) async throws -> String {
        await soundClient.play(.transcriptionStarted)
        let speed = model == selectedModelOption ? estimatedTranscriptionRTF : defaultTranscriptionRTF(for: model)
        startTranscriptionProgressTracking(expectedDuration: duration > 0 ? max(2, duration / max(speed, 0.2)) : 5)
        defer { stopTranscriptionProgressTracking() }
        let started = now
        if let stream {
            do {
                let text = try await stream.value
                stopTranscriptionProgressTracking()
                await floatingCapsuleClient.updateTranscriptionProgress(1)
                return text
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                logClient.error("AppModel", "Live transcription failed; retrying recorded audio: \(error.localizedDescription)")
            }
        }

        let text = try await transcriptionClient.transcribe(audioURL, model) { stage in
            await self.showProcessingStage(stage)
        }
        stopTranscriptionProgressTracking()
        let elapsed = now.timeIntervalSince(started)
        if model == selectedModelOption, duration > 0, elapsed > 0 {
            estimatedTranscriptionRTF = 0.75 * estimatedTranscriptionRTF + 0.25 * duration / elapsed
        }
        await floatingCapsuleClient.updateTranscriptionProgress(1)
        return text
    }

    private func noSpeechDetected() async {
        await soundClient.play(.transcriptionNoResult)
        logClient.debug("AppModel", "Empty transcription result — no speech detected")
    }

    private func transcriptionFailed(_ error: Error, sessionID: UUID) async {
        menuTransientMessage = "Transcription failed"
        sessionState = .error(error.localizedDescription)
        await floatingCapsuleClient.showError("Transcription failed")
        logClient.error("AppModel", "Transcription failed. sessionID=\(sessionID), error=\(error.localizedDescription)")
        await hideCapsuleAfterDelay()
    }

    private func showProcessingStage(_ stage: ProcessingStage) async {
        guard sessionState != .processing(stage) else { return }
        sessionState = .processing(stage)
        switch stage {
        case .trimming: await floatingCapsuleClient.showTrimming()
        case .speeding: await floatingCapsuleClient.showSpeeding()
        case .transcribing: await floatingCapsuleClient.showTranscribing()
        case .refining: await floatingCapsuleClient.showRefining()
        }
    }

    func hideCapsuleAfterDelay() async {
        try? await clock.sleep(for: .milliseconds(300))
        stopTranscriptionProgressTracking()
        await floatingCapsuleClient.hide()
        if case .error = sessionState { sessionState = .idle }
    }

    var isProcessing: Bool {
        if case .processing = sessionState { return true }
        return false
    }

    func normalizedTranscriptionMode(_ mode: TranscriptionMode, model: ModelOption? = nil) -> TranscriptionMode {
        guard let option = model ?? selectedModelOption else { return mode }
        return option.supportsTranscriptionMode(mode) ? mode : .verbatim
    }

    private func refine(
        _ transcript: String, using cleanup: CleanupModel?, prompt: String?, sessionID: UUID
    ) async -> String {
        guard let cleanup, !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return transcript }
        await showProcessingStage(.refining)
        do {
            switch cleanup {
            case .off:
                return transcript
            case .appleIntelligence:
                guard !FillerWords.isFillerOnly(transcript) else { return "" }
                let text = try await foundationModelClient.refine(transcript, prompt ?? smartPrompt)
                // The Apple framework can return an empty result when generation fails.
                return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? transcript : text
            case .petalW1:
                return try await localCleanupClient.clean(transcript)
            case .cloud:
                guard !FillerWords.isFillerOnly(transcript) else { return "" }
                guard var configuration = cloudCleanup.configuration else { return transcript }
                if let prompt { configuration.systemPrompt = prompt }
                return try await cloudCleanupClient.clean(transcript, configuration).text
            }
        } catch {
            logClient.error("AppModel", "\(cleanup.rawValue) cleanup failed for \(sessionID): \(error.localizedDescription)")
            if cleanup == .cloud { menuTransientMessage = "Cloud cleanup failed. Pasted original." }
            return transcript
        }
    }

    @discardableResult
    private func saveHistory(
        _ recording: HistoryRecording,
        mode: String,
        text: String,
        original: String? = nil,
        pasteResult: PasteResult,
        replacing entry: TranscriptHistoryEntry? = nil
    ) async -> Bool {
        let retention = historyRetentionMode
        guard retention.keepsHistory else { return true }
        let compress = compressHistoryAudio
        var variants = [(text: text, mode: mode, paste: pasteResult)]
        if let original {
            variants.append((original, TranscriptHistoryVariant.originalMode, .skipped))
        }
        var staged: [PersistedArtifacts] = []
        defer { staged.forEach(historyClient.discardArtifacts) }

        for variant in variants {
            let request = PersistArtifactsRequest(
                audioURL: recording.audioURL, transcript: variant.text, timestamp: recording.timestamp,
                mode: variant.mode, modelID: recording.modelID, retentionMode: retention,
                compressAudio: compress, persistAudio: entry == nil && staged.isEmpty
            )
            guard let paths = await historyClient.persistArtifacts(request) else { return false }
            staged.append(paths)
            guard historyRetentionMode == retention else { return !historyRetentionMode.keepsHistory }
        }
        let committed = $transcriptHistoryDays.withLock { days in
            if let entry, !days.contains(where: { $0.entries[id: entry.id] == entry }) { return false }
            for (index, variant) in variants.enumerated() {
                let paths = staged[index]
                days = historyClient.appendEntry(AppendEntryRequest(
                    currentDays: days, transcript: variant.text, modelID: recording.modelID, mode: variant.mode,
                    audioDuration: recording.duration, transcriptionElapsed: recording.elapsed,
                    pasteResult: variant.paste.rawValue, audioRelativePath: paths.audioRelativePath,
                    transcriptRelativePath: paths.transcriptRelativePath, retentionMode: retention,
                    timestamp: recording.timestamp, sessionID: recording.id, app: recording.app,
                    replacesVariants: entry != nil && index == 0
                ))
            }
            return true
        }
        if committed { staged.removeAll() }
        return committed
    }

    func postPasteFallbackNotification() async {
        await notificationClient.post("Transcript copied to clipboard. Press Command-V to paste.")
    }

    private func startTranscriptionProgressTracking(expectedDuration: Double) {
        stopTranscriptionProgressTracking()
        let start = now
        transcriptionProgressTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                let elapsed = max(now.timeIntervalSince(start) / expectedDuration, 0)
                let progress = elapsed <= 1
                    ? pow(elapsed, 0.72) * 0.94
                    : 0.94 + 0.055 * min((elapsed - 1) / 2, 1)
                await floatingCapsuleClient.updateTranscriptionProgress(progress)
                try? await clock.sleep(for: .milliseconds(120))
            }
        }
    }

    func stopTranscriptionProgressTracking() {
        transcriptionProgressTask?.cancel()
        transcriptionProgressTask = nil
    }

    func defaultTranscriptionRTF(for model: ModelOption?) -> Double {
        switch model {
        case .qwen3ASR17B8bit, .mini3b8bit: 1.5
        case .parakeetUnified06B, .nemotronUnified06B, .parakeetTDT06BV3: 2.0
        case .parakeetTDTCTC110M: 2.5
        case .whisperLargeV3Turbo: 0.85
        case .appleSpeech: 2.6
        case nil: 2.2
        }
    }
}

private struct HistoryRecording {
    let id: UUID
    let audioURL: URL
    let modelID: String
    let timestamp: Date
    let duration: TimeInterval
    let elapsed: TimeInterval
    let app: FocusedApp?
}

private enum AudioFileOrigin {
    case dropped
    case recovered
    case history(TranscriptHistoryEntry, cleansUp: Bool)

    var isRecovered: Bool {
        if case .recovered = self { return true }
        return false
    }

    var historyEntry: TranscriptHistoryEntry? {
        if case let .history(entry, _) = self { return entry }
        return nil
    }

    var requestsCleanup: Bool {
        if case .history(_, cleansUp: true) = self { return true }
        return false
    }
}

enum AppTranscriptionError: LocalizedError {
    case pipelineUnavailable

    var errorDescription: String? { "Transcription pipeline is not available." }
}
