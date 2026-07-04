@preconcurrency import AVFoundation
import Dependencies
import DependenciesMacros
import Foundation
import Shared

enum AudioClientError: LocalizedError, Sendable {
    case notRecording
    case failedToStart

    var errorDescription: String? {
        switch self {
        case .notRecording:
            return "No recording is currently active."
        case .failedToStart:
            return "Petal could not start recording audio."
        }
    }
}

public struct AudioInputDevice: Identifiable, Hashable, Sendable {
    public static let systemDefaultID = "system-default"

    public let id: String
    public let name: String
    public let isSystemDefault: Bool

    public init(id: String, name: String, isSystemDefault: Bool = false) {
        self.id = id
        self.name = name
        self.isSystemDefault = isSystemDefault
    }
}

@DependencyClient
public struct AudioClient: Sendable {
    public var isRecording: @Sendable () async -> Bool = { false }
    public var warmup: @Sendable () -> Void = {}
    public var availableInputDevices: @Sendable () async -> [AudioInputDevice] = { [] }
    public var startRecording: @Sendable (@escaping @Sendable (Double) -> Void) async throws -> Void
    public var stopRecording: @Sendable () async throws -> URL
    public var cancelRecording: @Sendable () async -> Void = {}
}

extension AudioClient: DependencyKey {
    public static var liveValue: Self {
        return Self(
            isRecording: {
                LiveAudioCaptureRuntimeContainer.shared.isRecording
            },
            warmup: {
                LiveAudioCaptureRuntimeContainer.shared.warmup()
            },
            availableInputDevices: {
                LiveAudioCaptureRuntime.availableInputDevices()
            },
            startRecording: { levelHandler in
                try await LiveAudioCaptureRuntimeContainer.shared.startRecording(levelHandler: levelHandler)
            },
            stopRecording: {
                try await LiveAudioCaptureRuntimeContainer.shared.stopRecording()
            },
            cancelRecording: {
                await LiveAudioCaptureRuntimeContainer.shared.cancelRecording()
            }
        )
    }
}

extension AudioClient: TestDependencyKey {
    public static var testValue: Self {
        Self(
            isRecording: { false },
            warmup: {},
            availableInputDevices: {
                [
                    AudioInputDevice(
                        id: AudioInputDevice.systemDefaultID,
                        name: "System Default",
                        isSystemDefault: true
                    )
                ]
            },
            startRecording: { _ in },
            stopRecording: { URL(fileURLWithPath: "/dev/null") },
            cancelRecording: {}
        )
    }
}

public extension DependencyValues {
    var audioClient: AudioClient {
        get { self[AudioClient.self] }
        set { self[AudioClient.self] = newValue }
    }
}

/// Thread-safe envelope follower with auto-gain, captured by the audio tap
/// closure so that `LiveAudioCaptureRuntime` is never referenced from the
/// real-time audio thread.
///
/// Envelope: rising levels jump most of the way toward the new sample so
/// speech transients register immediately; falling levels ease down slowly so
/// the meter reads naturally instead of flickering.
///
/// Auto-gain: mics differ wildly in how hot they meter — the MacBook's
/// built-in mic reports normal speech ~15 dB quieter than a typical headset.
/// The processor tracks the loudest recent envelope as an adaptive ceiling
/// and normalizes against it, so a quiet mic still swings the meter across
/// its full range instead of hovering near the middle. `minCeiling` bounds
/// the boost so room noise on a silent mic is never amplified into speech.
private final class LevelProcessor: @unchecked Sendable {
    private var envelope: Double = 0
    private var ceiling: Double = LevelProcessor.minCeiling
    private let lock = NSLock()

    private static let attack: Double = 0.7
    private static let decay: Double = 0.18
    /// Levels below this fraction of the adaptive range read as silence, so
    /// steady room noise doesn't keep the meter twitching.
    private static let gate: Double = 0.08
    /// Lowest reference the auto-gain may normalize against (bounds the boost
    /// at roughly 2.5×).
    private static let minCeiling: Double = 0.42
    /// Per-sample ceiling decay at the ~60 ms metering cadence — the reference
    /// slides back down over ~30 s so one loud clap doesn't deafen the meter.
    private static let ceilingDecay: Double = 0.9985

    func process(_ level: Double) -> Double {
        lock.lock()
        defer { lock.unlock() }
        let clamped = max(0, min(1, level))
        let coefficient = clamped > envelope ? Self.attack : Self.decay
        envelope += (clamped - envelope) * coefficient
        ceiling = max(envelope, ceiling * Self.ceilingDecay, Self.minCeiling)
        let normalized = (envelope - Self.gate) / (ceiling - Self.gate)
        return max(0, min(1, normalized))
    }
}

private final class LiveAudioCaptureRuntime: @unchecked Sendable {
    private let stateQueue = DispatchQueue(label: "com.petal.audio.capture.runtime")
    private var recorder: AVAudioRecorder?
    private var selectedInputRecording: SelectedInputAudioRecording?
    private var standbyRecorder: AVAudioRecorder?
    private var standbyURL: URL?
    private var simulatedRecordingSourceURL: URL?
    private var recordingURL: URL?
    private var levelHandler: @Sendable (Double) -> Void = { _ in }
    private var levelTimer: DispatchSourceTimer?
    private let levelProcessor = LevelProcessor()

    private nonisolated(unsafe) static let recordingSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: 44_100,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false
    ]

    var isRecording: Bool {
        stateQueue.sync {
            if simulatedRecordingSourceURL != nil {
                return true
            }
            if selectedInputRecording != nil {
                return true
            }
            return recorder?.isRecording ?? false
        }
    }

    /// Pre-creates and prepares an AVAudioRecorder so the next
    /// `startRecording` call only needs to call `record()`.
    func warmup() {
        stateQueue.async { [self] in
            warmupStandbyLocked()
        }
    }

    func startRecording(levelHandler: @escaping @Sendable (Double) -> Void) async throws {
        try await withCheckedThrowingContinuation { continuation in
            stateQueue.async { [self] in
                do {
                    try startRecordingLocked(levelHandler: levelHandler)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func warmupStandbyLocked() {
        guard standbyRecorder == nil, recorder == nil else { return }
        guard Self.e2eAudioFixtureURL() == nil else { return }
        guard Self.selectedInputDeviceIDForRecording() == AudioInputDevice.systemDefaultID else { return }

        let url = FileManager.default.temporaryDirectory
            .appending(path: "petal-\(UUID().uuidString).wav")
        do {
            let rec = try AVAudioRecorder(url: url, settings: Self.recordingSettings)
            rec.isMeteringEnabled = true
            guard rec.prepareToRecord() else { return }
            standbyRecorder = rec
            standbyURL = url
        } catch {}
    }

    private func startRecordingLocked(levelHandler: @escaping @Sendable (Double) -> Void) throws {
        guard recorder == nil, selectedInputRecording == nil, simulatedRecordingSourceURL == nil else { return }
        self.levelHandler = levelHandler

        if let e2eAudioURL = Self.e2eAudioFixtureURL() {
            simulatedRecordingSourceURL = e2eAudioURL
            recordingURL = e2eAudioURL
            startSimulatedLevelPollingLocked()
            return
        }

        if let selectedDevice = Self.selectedCaptureDeviceForRecording() {
            let audioURL = FileManager.default.temporaryDirectory
                .appending(path: "petal-\(UUID().uuidString).m4a")
            let recording = try SelectedInputAudioRecording(
                device: selectedDevice,
                outputURL: audioURL,
                levelHandler: levelHandler
            )
            try recording.start()
            selectedInputRecording = recording
            recordingURL = audioURL
            return
        }

        // Use pre-warmed standby recorder if available
        if let standby = standbyRecorder, let url = standbyURL {
            standbyRecorder = nil
            standbyURL = nil
            guard standby.record() else {
                throw AudioClientError.failedToStart
            }
            self.recorder = standby
            recordingURL = url
            startLevelPollingLocked()
            return
        }

        // Fallback: create fresh recorder
        let audioURL = FileManager.default.temporaryDirectory
            .appending(path: "petal-\(UUID().uuidString).wav")

        let recorder = try AVAudioRecorder(url: audioURL, settings: Self.recordingSettings)
        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord(), recorder.record() else {
            throw AudioClientError.failedToStart
        }

        self.recorder = recorder
        recordingURL = audioURL
        startLevelPollingLocked()
    }

    func stopRecording() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            stateQueue.async { [self] in
                do {
                    let url = try stopRecordingLocked()
                    continuation.resume(returning: url)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func stopRecordingLocked() throws -> URL {
        if let fixtureURL = simulatedRecordingSourceURL {
            return try stopSimulatedRecordingLocked(sourceURL: fixtureURL)
        }

        if let selectedInputRecording {
            let url = try selectedInputRecording.stop()
            self.selectedInputRecording = nil
            recordingURL = nil
            levelHandler(0)
            return url
        }

        guard let recorder, let url = recordingURL else {
            throw AudioClientError.notRecording
        }

        recorder.stop()
        stopLevelPollingLocked()
        self.recorder = nil
        recordingURL = nil
        levelHandler(0)

        // Pre-warm next standby recorder in the background
        stateQueue.asyncAfter(deadline: .now() + 0.1) { [self] in
            warmupStandbyLocked()
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64 ?? 0

        guard fileSize > 44 else {
            try? FileManager.default.removeItem(at: url)
            throw AudioClientError.failedToStart
        }

        return url
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
            stopLevelPollingLocked()
            simulatedRecordingSourceURL = nil
            recordingURL = nil
            levelHandler(0)
            return
        }

        if let selectedInputRecording {
            selectedInputRecording.cancel()
            let url = recordingURL
            self.selectedInputRecording = nil
            recordingURL = nil
            levelHandler(0)
            if let url {
                try? FileManager.default.removeItem(at: url)
            }
            return
        }

        guard let recorder else { return }

        recorder.stop()
        stopLevelPollingLocked()

        let url = recordingURL
        self.recorder = nil
        recordingURL = nil
        levelHandler(0)
        if let url {
            try? FileManager.default.removeItem(at: url)
        }

        // Pre-warm next standby recorder in the background
        stateQueue.asyncAfter(deadline: .now() + 0.1) { [self] in
            warmupStandbyLocked()
        }
    }

    private func stopSimulatedRecordingLocked(sourceURL: URL) throws -> URL {
        stopLevelPollingLocked()
        simulatedRecordingSourceURL = nil
        recordingURL = nil
        levelHandler(0)

        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "petal-e2e-\(UUID().uuidString).wav")
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: outputURL)

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path))?[.size] as? Int64 ?? 0
        guard fileSize > 44 else {
            try? FileManager.default.removeItem(at: outputURL)
            throw AudioClientError.failedToStart
        }
        return outputURL
    }

    private func startSimulatedLevelPollingLocked() {
        levelTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: stateQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(60))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let smoothed = self.levelProcessor.process(0.34)
            let handler = self.levelHandler
            DispatchQueue.main.async {
                handler(smoothed)
            }
        }
        levelTimer = timer
        timer.resume()
    }

    private func startLevelPollingLocked() {
        levelTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: stateQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(60))
        timer.setEventHandler { [weak self] in
            guard let self, let recorder = self.recorder, recorder.isRecording else { return }
            recorder.updateMeters()
            let power = recorder.averagePower(forChannel: 0)
            let normalized = Self.normalizePower(power)
            let smoothed = self.levelProcessor.process(normalized)
            let handler = self.levelHandler
            DispatchQueue.main.async {
                handler(smoothed)
            }
        }
        levelTimer = timer
        timer.resume()
    }

    private func stopLevelPollingLocked() {
        levelTimer?.cancel()
        levelTimer = nil
    }

    nonisolated fileprivate static func normalizePower(_ power: Float) -> Double {
        if power <= -58 {
            return 0
        }
        // Map -58 dBFS -> 0.0 and -18 dBFS -> 1.0. The built-in MacBook mic
        // meters normal speech around -45...-30 dBFS, so the narrower window
        // (vs the old -60...-10) puts speech in the upper half of the range;
        // LevelProcessor's auto-gain then stretches it to full scale.
        let normalized = (Double(power) + 58.0) / 40.0
        return max(0, min(1, normalized))
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
        let defaultDeviceID = AVCaptureDevice.default(for: .audio)?.uniqueID
        let systemDefaultName = AVCaptureDevice.default(for: .audio)?.localizedName ?? "System Default"

        var inputDevices = [
            AudioInputDevice(
                id: AudioInputDevice.systemDefaultID,
                name: "System Default (\(systemDefaultName))",
                isSystemDefault: true
            )
        ]

        for device in devices.sorted(by: { $0.localizedName.localizedCaseInsensitiveCompare($1.localizedName) == .orderedAscending }) {
            guard !inputDevices.contains(where: { $0.id == device.uniqueID }) else { continue }
            let name = device.uniqueID == defaultDeviceID
                ? "\(device.localizedName) (Current Default)"
                : device.localizedName
            inputDevices.append(
                AudioInputDevice(
                    id: device.uniqueID,
                    name: name,
                    isSystemDefault: device.uniqueID == defaultDeviceID
                )
            )
        }

        return inputDevices
    }

    nonisolated private static func selectedInputDeviceIDForRecording() -> String {
        @Shared(.selectedAudioInputDeviceID) var selectedInputDeviceID = AudioInputDevice.systemDefaultID
        let trimmed = selectedInputDeviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AudioInputDevice.systemDefaultID : trimmed
    }

    nonisolated private static func selectedCaptureDeviceForRecording() -> AVCaptureDevice? {
        let selectedID = selectedInputDeviceIDForRecording()
        guard selectedID != AudioInputDevice.systemDefaultID else { return nil }
        return inputCaptureDevices()
            .first(where: { $0.uniqueID == selectedID })
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

private final class SelectedInputAudioRecording: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let captureQueue = DispatchQueue(label: "com.petal.audio.capture.selected-input")
    private let writer: AVAssetWriter
    private let writerInput: AVAssetWriterInput
    private let outputURL: URL
    private let levelHandler: @Sendable (Double) -> Void
    private let levelProcessor = LevelProcessor()
    private var didStartWriting = false
    private var isStopping = false

    init(
        device: AVCaptureDevice,
        outputURL: URL,
        levelHandler: @escaping @Sendable (Double) -> Void
    ) throws {
        self.outputURL = outputURL
        self.levelHandler = levelHandler
        writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
        writerInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 128_000
            ]
        )
        writerInput.expectsMediaDataInRealTime = true
        super.init()

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input), session.canAddOutput(audioOutput), writer.canAdd(writerInput) else {
            throw AudioClientError.failedToStart
        }

        session.beginConfiguration()
        session.addInput(input)
        audioOutput.setSampleBufferDelegate(self, queue: captureQueue)
        session.addOutput(audioOutput)
        session.commitConfiguration()
        writer.add(writerInput)
    }

    func start() throws {
        session.startRunning()
        guard session.isRunning else {
            throw AudioClientError.failedToStart
        }
    }

    func stop() throws -> URL {
        session.stopRunning()
        return try captureQueue.sync {
            isStopping = true
            guard didStartWriting else {
                writer.cancelWriting()
                throw AudioClientError.failedToStart
            }

            writerInput.markAsFinished()
            let result = FinishWritingResult()
            let semaphore = DispatchSemaphore(value: 0)
            writer.finishWriting {
                result.error = self.writer.error
                semaphore.signal()
            }
            semaphore.wait()

            if let error = result.error {
                throw error
            }

            let fileSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path))?[.size] as? Int64 ?? 0
            guard fileSize > 0 else {
                try? FileManager.default.removeItem(at: outputURL)
                throw AudioClientError.failedToStart
            }

            return outputURL
        }
    }

    func cancel() {
        session.stopRunning()
        captureQueue.sync {
            isStopping = true
            writer.cancelWriting()
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard !isStopping else { return }

        if !didStartWriting {
            guard writer.startWriting() else { return }
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            didStartWriting = true
        }

        if writerInput.isReadyForMoreMediaData {
            writerInput.append(sampleBuffer)
        }

        if let channel = connection.audioChannels.first {
            let normalized = LiveAudioCaptureRuntime.normalizePower(channel.averagePowerLevel)
            let smoothed = levelProcessor.process(normalized)
            let handler = levelHandler
            DispatchQueue.main.async {
                handler(smoothed)
            }
        }
    }
}

private final class FinishWritingResult: @unchecked Sendable {
    var error: Error?
}

private enum LiveAudioCaptureRuntimeContainer {
    static let shared = LiveAudioCaptureRuntime()
}
