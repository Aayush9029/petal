@preconcurrency import AVFoundation
import Foundation
import OSLog
import Shared

final class SelectedInputAudioRecording: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    let device: AVCaptureDevice
    let streaming: Bool
    private let session = AVCaptureSession()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let captureQueue = DispatchQueue(label: "com.petal.audio.capture.selected-input")
    private let writer: AVAssetWriter
    private let writerInput: AVAssetWriterInput
    let outputURL: URL
    private var levelHandler: @Sendable (Double) -> Void = { _ in }
    private var levelProcessor = LevelProcessor()
    private var sampleProducer: AudioSampleProducer?
    private var didStartWriting = false
    private var isStopping = false
    private var runtimeErrorObserver: (any NSObjectProtocol)?

    init(
        device: AVCaptureDevice,
        outputURL: URL,
        streaming: Bool = false
    ) throws {
        self.device = device
        self.streaming = streaming
        self.outputURL = outputURL
        (writer, writerInput) = try Self.makeWriter(outputURL: outputURL)
        super.init()

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input), session.canAddOutput(audioOutput), writer.canAdd(writerInput) else {
            throw AudioClientError.failedToStart
        }

        session.beginConfiguration()
        session.addInput(input)
        // Stereo and multichannel devices make the mono AAC writer fail, so the output always converts to mono.
        audioOutput.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: streaming ? speechSampleRate : 44_100,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
        ]
        audioOutput.setSampleBufferDelegate(self, queue: captureQueue)
        session.addOutput(audioOutput)
        session.commitConfiguration()
        writer.add(writerInput)

        // startRunning reports its failures only through this notification.
        let deviceName = device.localizedName
        runtimeErrorObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil
        ) { notification in
            let error = notification.userInfo?[AVCaptureSessionErrorKey] as? Error
            audioCaptureLogger.error("Capture session error on \(deviceName, privacy: .public): \(error?.localizedDescription ?? "unknown", privacy: .public)")
        }
    }

    deinit {
        if let runtimeErrorObserver { NotificationCenter.default.removeObserver(runtimeErrorObserver) }
    }

    static func makeWriter(outputURL: URL) throws -> (AVAssetWriter, AVAssetWriterInput) {
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
        // Fragments keep the file readable if Petal quits before the writer finishes.
        writer.movieFragmentInterval = CMTime(seconds: 0.5, preferredTimescale: 600)
        let input = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 128_000
            ]
        )
        input.expectsMediaDataInRealTime = true
        return (writer, input)
    }

    func start(
        levelHandler: @escaping @Sendable (Double) -> Void,
        sampleProducer: AudioSampleProducer? = nil
    ) throws {
        guard streaming == (sampleProducer != nil) else { throw AudioClientError.invalidStreamFormat }
        captureQueue.sync {
            self.levelHandler = levelHandler
            self.sampleProducer = sampleProducer
        }
        session.startRunning()
        guard session.isRunning else {
            throw AudioClientError.failedToStart
        }
    }

    func stop() throws -> URL {
        session.stopRunning()
        return try captureQueue.sync {
            isStopping = true
            // stopRunning followed by this barrier drains every queued capture callback.
            sampleProducer?.finish()
            guard didStartWriting else {
                throw AudioClientError.failedToStart
            }

            writerInput.markAsFinished()
            let semaphore = DispatchSemaphore(value: 0)
            writer.finishWriting {
                semaphore.signal()
            }
            semaphore.wait()

            if let error = writer.error {
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
            sampleProducer?.finish(throwing: CancellationError())
            if didStartWriting { writer.cancelWriting() }
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard !isStopping else { return }
        sampleProducer?.append(sampleBuffer)

        if !didStartWriting {
            guard writer.startWriting() else { return }
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            didStartWriting = true
        }

        if writerInput.isReadyForMoreMediaData {
            writerInput.append(sampleBuffer)
        }

        if let channel = connection.audioChannels.first {
            let normalized = LevelProcessor.normalizePower(channel.averagePowerLevel)
            let smoothed = levelProcessor.process(normalized)
            let handler = levelHandler
            DispatchQueue.main.async {
                handler(smoothed)
            }
        }
    }
}
