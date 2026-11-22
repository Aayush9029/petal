@preconcurrency import AVFoundation
import Foundation

enum HardwareRecording {
    case recorder(AVAudioRecorder)
    case capture(SelectedInputAudioRecording)

    var url: URL {
        switch self {
        case .recorder(let recorder): recorder.url
        case .capture(let capture): capture.outputURL
        }
    }

    var captureDevice: AVCaptureDevice? {
        guard case .capture(let capture) = self else { return nil }
        return capture.device
    }

    var isRecording: Bool {
        switch self {
        case .recorder(let recorder): recorder.isRecording
        case .capture: true
        }
    }

    init(device: AVCaptureDevice?, streaming: Bool) throws {
        let url = RecordingFiles.newURL(extension: device == nil ? "wav" : "m4a")
        do {
            if let device {
                self = .capture(try SelectedInputAudioRecording(device: device, outputURL: url, streaming: streaming))
            } else {
                guard !streaming else { throw AudioClientError.failedToStart }
                let recorder = try AVAudioRecorder(url: url, settings: Self.recordingSettings)
                recorder.isMeteringEnabled = true
                guard recorder.prepareToRecord() else { throw AudioClientError.failedToStart }
                self = .recorder(recorder)
            }
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    func discard() {
        switch self {
        case .recorder(let recorder): recorder.stop()
        case .capture(let capture): capture.cancel()
        }
        try? FileManager.default.removeItem(at: url)
    }

    private nonisolated(unsafe) static let recordingSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: 44_100,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false
    ]
}
