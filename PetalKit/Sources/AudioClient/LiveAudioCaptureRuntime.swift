@preconcurrency import AVFoundation
import CoreAudio
import Foundation
import OSLog
import Shared

let audioCaptureLogger = Logger(subsystem: "com.optimalapps.petal", category: "AudioClient")

// Capture state is confined to stateQueue.
final class LiveAudioCaptureRuntime: @unchecked Sendable {
    static let shared = LiveAudioCaptureRuntime()

    private let stateQueue = DispatchQueue(label: "com.petal.audio.capture.runtime", qos: .userInitiated)
    private let audioFixtureURL: @Sendable () -> URL?
    private var activeRecording: HardwareRecording?
    private var standby: (configuration: AudioCaptureConfiguration, recording: HardwareRecording)?
    private var standbyStreams = false
    private var captureFallbackInputUID: String?
    private var inputChangeObservers: [any NSObjectProtocol] = []
    private var defaultInputListener: AudioObjectPropertyListenerBlock?
    private var simulatedRecordingSourceURL: URL?
    private var simulatedSamples: [Float] = []
    private var simulatedSampleOffset = 0
    private var simulatedProducer: AudioSampleProducer?
    private var levelHandler: @Sendable (Double) -> Void = { _ in }
    private var levelTimer: DispatchSourceTimer?
    private var levelProcessor = LevelProcessor()

    init(audioFixtureURL: @escaping @Sendable () -> URL? = LiveAudioCaptureRuntime.e2eAudioFixtureURL) {
        self.audioFixtureURL = audioFixtureURL
    }

    deinit {
        for observer in inputChangeObservers { NotificationCenter.default.removeObserver(observer) }
        if let defaultInputListener {
            var address = Self.defaultInputAddress
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, stateQueue, defaultInputListener)
        }
    }

    func isRecording() async -> Bool {
        await withCheckedContinuation { continuation in
            stateQueue.async { [self] in
                continuation.resume(returning: simulatedRecordingSourceURL != nil
                    || activeRecording?.isRecording == true)
            }
        }
    }

    func warmup(streaming: Bool) {
        stateQueue.async { [self] in
            standbyStreams = streaming
            warmupStandbyLocked()
        }
    }

    func startRecording(levelHandler: @escaping @Sendable (Double) -> Void) async throws {
        _ = try await start(streaming: false, levelHandler: levelHandler)
    }

    func startStreamingRecording(levelHandler: @escaping @Sendable (Double) -> Void) async throws -> AudioSampleStream {
        guard let stream = try await start(streaming: true, levelHandler: levelHandler) else {
            throw AudioClientError.failedToStart
        }
        return stream
    }

    private func start(streaming: Bool, levelHandler: @escaping @Sendable (Double) -> Void) async throws -> AudioSampleStream? {
        try await withCheckedThrowingContinuation { continuation in
            stateQueue.async { [self] in
                continuation.resume(with: Result {
                    try AudioRecordingStartup.start(streaming: streaming) { producer in
                        try startRecordingLocked(levelHandler: levelHandler, sampleProducer: producer)
                    }
                })
            }
        }
    }

    private func warmupStandbyLocked() {
        guard activeRecording == nil, simulatedRecordingSourceURL == nil else { return }
        guard audioFixtureURL() == nil else { return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }
        observeInputChangesLocked()
        let streaming = standbyStreams
        let configuration = Self.captureConfiguration(streaming: streaming)
        if standbyMatches(configuration) { return }
        discardStandbyLocked()

        do {
            let needsCaptureFallback = configuration.usesSystemDefault
                && configuration.defaultInputUID != nil && captureFallbackInputUID == configuration.defaultInputUID
            let device = Self.selectedCaptureDeviceForRecording(inputID: configuration.inputDeviceID)
                ?? (streaming || needsCaptureFallback
                    ? Self.fallbackCaptureDevice(defaultInputUID: configuration.defaultInputUID) : nil)
            standby = (configuration, try HardwareRecording(device: device, streaming: streaming))
        } catch {
            audioCaptureLogger.debug("Audio preparation failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func observeInputChangesLocked() {
        guard inputChangeObservers.isEmpty else { return }
        let rewarm: @Sendable () -> Void = { [weak self] in self?.scheduleWarmup() }
        inputChangeObservers = [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification].map {
            NotificationCenter.default.addObserver(forName: $0, object: nil, queue: nil) { _ in rewarm() }
        }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.warmupStandbyLocked() }
        var address = Self.defaultInputAddress
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, stateQueue, listener) == noErr {
            defaultInputListener = listener
        }
    }

    private func standbyMatches(_ configuration: AudioCaptureConfiguration) -> Bool {
        guard let standby else { return false }
        let device = standby.recording.captureDevice
        return standby.configuration.canReuse(
            for: configuration, captureDeviceID: device?.uniqueID, captureDeviceIsConnected: device?.isConnected ?? true
        )
    }

    private func discardStandbyLocked() {
        standby?.recording.discard()
        standby = nil
    }

    private func startRecordingLocked(
        levelHandler: @escaping @Sendable (Double) -> Void,
        sampleProducer: AudioSampleProducer? = nil
    ) throws {
        guard activeRecording == nil, simulatedRecordingSourceURL == nil else {
            throw AudioClientError.failedToStart
        }
        self.levelHandler = levelHandler

        if let e2eAudioURL = audioFixtureURL() {
            if let sampleProducer {
                simulatedSamples = try AudioSampleProducer.readFixture(e2eAudioURL)
                simulatedSampleOffset = 0
                simulatedProducer = sampleProducer
            }
            simulatedRecordingSourceURL = e2eAudioURL
            startLevelPollingLocked()
            return
        }

        standbyStreams = sampleProducer != nil
        let configuration = Self.captureConfiguration(streaming: standbyStreams)
        if !standbyMatches(configuration) { discardStandbyLocked() }
        let prepared = standby?.recording
        standby = nil
        let device = prepared?.captureDevice ?? Self.selectedCaptureDeviceForRecording(inputID: configuration.inputDeviceID)
            ?? (standbyStreams ? Self.fallbackCaptureDevice(defaultInputUID: configuration.defaultInputUID) : nil)
        do {
            let recording = try prepared ?? HardwareRecording(device: device, streaming: standbyStreams)
            try activate(recording, sampleProducer: sampleProducer)
        } catch {
            if prepared?.captureDevice != nil {
                audioCaptureLogger.warning("Prepared capture failed; retrying a fresh session: \(error.localizedDescription, privacy: .public)")
                throw PreparedCaptureStartFailure.unavailable
            }
            // CoreAudio's default recorder can retain a disconnected USB or Bluetooth microphone.
            guard device == nil, !standbyStreams,
                  let fallback = Self.fallbackCaptureDevice(defaultInputUID: configuration.defaultInputUID)
            else { throw error }
            try activate(HardwareRecording(device: fallback, streaming: false), sampleProducer: nil)
            captureFallbackInputUID = configuration.defaultInputUID
        }
    }

    private func activate(_ recording: HardwareRecording, sampleProducer: AudioSampleProducer?) throws {
        do {
            switch recording {
            case .capture(let capture):
                try capture.start(levelHandler: levelHandler, sampleProducer: sampleProducer)
            case .recorder(let recorder):
                guard recorder.record() else { throw AudioClientError.failedToStart }
            }
            activeRecording = recording
            if case .recorder = recording { startLevelPollingLocked() }
        } catch {
            recording.discard()
            throw error
        }
    }

    func unfinishedRecordings() async -> [URL] {
        await withCheckedContinuation { continuation in
            stateQueue.async { [self] in
                let active = Set([standby?.recording.url, activeRecording?.url, simulatedRecordingSourceURL].compactMap { $0?.standardizedFileURL })
                continuation.resume(returning: RecordingFiles.unfinished(excluding: active))
            }
        }
    }

    func stopRecording() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            stateQueue.async { [self] in
                continuation.resume(with: Result { try stopRecordingLocked() })
            }
        }
    }

    private func stopRecordingLocked() throws -> URL {
        if let fixtureURL = simulatedRecordingSourceURL {
            return try stopSimulatedRecordingLocked(sourceURL: fixtureURL)
        }

        guard let activeRecording else { throw AudioClientError.notRecording }
        defer { finishHardwareRecording() }
        switch activeRecording {
        case .capture(let capture):
            return try capture.stop()
        case .recorder(let recorder):
            recorder.stop()
            return try RecordingFiles.finishedWAV(at: recorder.url)
        }
    }

    private func finishHardwareRecording() {
        activeRecording = nil
        stopLevelPollingLocked()
        levelHandler(0)
        scheduleWarmup()
    }

    func cancelRecording() async {
        await withCheckedContinuation { continuation in
            stateQueue.async { [self] in
                cancelRecordingLocked()
                continuation.resume()
            }
        }
    }

    private func cancelRecordingLocked() {
        if simulatedRecordingSourceURL != nil {
            simulatedProducer?.finish(throwing: CancellationError())
            simulatedProducer = nil
            simulatedSamples.removeAll()
            stopLevelPollingLocked()
            simulatedRecordingSourceURL = nil
            levelHandler(0)
            return
        }

        guard let activeRecording else { return }
        activeRecording.discard()
        finishHardwareRecording()
    }

    private func scheduleWarmup() {
        stateQueue.async { [weak self] in
            self?.warmupStandbyLocked()
        }
    }

    private func stopSimulatedRecordingLocked(sourceURL: URL) throws -> URL {
        stopLevelPollingLocked()
        // An unattended recording consumes the whole fixture, even when stopped immediately.
        simulatedProducer?.append(Array(simulatedSamples.dropFirst(simulatedSampleOffset)))
        simulatedProducer?.finish()
        simulatedProducer = nil
        simulatedSamples.removeAll()
        simulatedRecordingSourceURL = nil
        levelHandler(0)

        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "petal-e2e-\(UUID().uuidString).wav")
        try FileManager.default.copyItem(at: sourceURL, to: outputURL)
        return try RecordingFiles.finishedWAV(at: outputURL)
    }

    private static let meterIntervalMilliseconds = 60

    private func startLevelPollingLocked() {
        levelTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: stateQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(Self.meterIntervalMilliseconds))
        timer.setEventHandler { [weak self] in self?.pollLevelLocked() }
        levelTimer = timer
        timer.resume()
    }

    private func pollLevelLocked() {
        let level: Double
        if simulatedRecordingSourceURL != nil {
            if let simulatedProducer, simulatedSampleOffset < simulatedSamples.count {
                let end = min(simulatedSampleOffset + speechSampleRate * Self.meterIntervalMilliseconds / 1_000, simulatedSamples.count)
                simulatedProducer.append(Array(simulatedSamples[simulatedSampleOffset..<end]))
                simulatedSampleOffset = end
            }
            level = 0.34
        } else if case let .recorder(recorder) = activeRecording, recorder.isRecording {
            recorder.updateMeters()
            level = LevelProcessor.normalizePower(recorder.averagePower(forChannel: 0))
        } else {
            return
        }
        let smoothed = levelProcessor.process(level)
        let handler = levelHandler
        DispatchQueue.main.async { handler(smoothed) }
    }

    private func stopLevelPollingLocked() {
        levelTimer?.cancel()
        levelTimer = nil
    }

    nonisolated private static func e2eAudioFixtureURL() -> URL? {
        let environment = ProcessInfo.processInfo.environment
        if let path = environment["PETAL_E2E_AUDIO_FILE"], !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        if let path = UserDefaults.standard.string(forKey: "e2e_audio_file"), !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        return nil
    }

    nonisolated static func availableInputDevices() -> [AudioInputDevice] {
        let devices = inputCaptureDevices()
        var inputDevices: [AudioInputDevice] = [.systemDefault]
        for device in devices.sorted(by: { $0.localizedName.localizedCaseInsensitiveCompare($1.localizedName) == .orderedAscending }) {
            guard !inputDevices.contains(where: { $0.id == device.uniqueID }) else { continue }
            inputDevices.append(AudioInputDevice(id: device.uniqueID, name: device.localizedName))
        }
        return inputDevices
    }

    nonisolated private static func selectedInputDeviceIDForRecording() -> String {
        @SharedReader(.selectedAudioInputDeviceID) var selectedInputDeviceID
        let trimmed = selectedInputDeviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AudioInputDevice.systemDefaultID : trimmed
    }

    nonisolated private static func captureConfiguration(streaming: Bool) -> AudioCaptureConfiguration {
        AudioCaptureConfiguration(
            inputDeviceID: selectedInputDeviceIDForRecording(),
            defaultInputUID: coreAudioDefaultInputUID(), streaming: streaming
        )
    }

    nonisolated private static func selectedCaptureDeviceForRecording(inputID: String) -> AVCaptureDevice? {
        guard inputID != AudioInputDevice.systemDefaultID else { return nil }
        return inputCaptureDevices()
            .first(where: { $0.uniqueID == inputID })
    }

    nonisolated private static func fallbackCaptureDevice(defaultInputUID: String?) -> AVCaptureDevice? {
        let devices = inputCaptureDevices().filter(\.isConnected)
        // AVCaptureDevice.default can differ from the input that the user set in System Settings.
        if let defaultUID = defaultInputUID,
           let match = devices.first(where: { $0.uniqueID == defaultUID }) {
            return match
        }
        if let systemDefault = AVCaptureDevice.default(for: .audio),
           let match = devices.first(where: { $0.uniqueID == systemDefault.uniqueID }) {
            return match
        }
        return devices.first
    }

    nonisolated private static let defaultInputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    nonisolated private static func coreAudioDefaultInputUID() -> String? {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = defaultInputAddress
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr,
              deviceID != kAudioObjectUnknown
        else { return nil }

        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        address.mSelector = kAudioDevicePropertyDeviceUID
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &uid) == noErr else { return nil }
        return uid?.takeRetainedValue() as String?
    }

    nonisolated private static func inputCaptureDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        .devices
    }
}
