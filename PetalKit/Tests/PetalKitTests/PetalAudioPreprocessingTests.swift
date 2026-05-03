import AVFoundation
import Dependencies
import Foundation
import Shared
import Testing
@testable import AudioSpeedClient
@testable import AudioTrimClient
@testable import LogClient
@testable import MLXClient
@testable import TranscriptionClient

@Test
func trimSilenceRemovesLeadingAndTrailingSections() async throws {
    let sampleRate = 16_000.0
    let silence = Array(repeating: Float(0), count: 2_000)
    let tone = makeSineWave(count: 3_000, sampleRate: sampleRate, amplitude: 0.6, frequency: 220)
    let inputURL = try writeAudio(samples: silence + tone + silence, sampleRate: sampleRate, prefix: "trim-input")
    defer { try? FileManager.default.removeItem(at: inputURL) }

    let outputURL = try await AudioTrimClient.liveValue.trimSilence(inputURL, 0.01)
    defer { try? FileManager.default.removeItem(at: outputURL) }

    #expect(outputURL != inputURL)

    let inputDuration = try audioDuration(inputURL)
    let outputDuration = try audioDuration(outputURL)
    #expect(outputDuration < inputDuration)
    #expect(outputDuration > 0.15)
    #expect(outputDuration < 0.25)
}

@Test
func speedUpReducesDurationAtExpectedRate() async throws {
    let sampleRate = 16_000.0
    let samples = makeSineWave(count: 32_000, sampleRate: sampleRate, amplitude: 0.5, frequency: 330)
    let inputURL = try writeAudio(samples: samples, sampleRate: sampleRate, prefix: "speed-input")
    defer { try? FileManager.default.removeItem(at: inputURL) }

    let outputURL = try await AudioSpeedClient.liveValue.speedUp(inputURL, 1.25)
    defer { try? FileManager.default.removeItem(at: outputURL) }

    #expect(outputURL != inputURL)

    let inputDuration = try audioDuration(inputURL)
    let outputDuration = try audioDuration(outputURL)
    let ratio = outputDuration / inputDuration

    #expect(ratio > 0.75)
    #expect(ratio < 0.85)
}

@Test
func transcriptionClientUsesTrimAndSpeedDependenciesBeforeMLX() async throws {
    let recorder = CallRecorder()
    let appStorage = UserDefaults.inMemory
    let sampleRate = 16_000.0
    let samples = makeSineWave(count: 800_000, sampleRate: sampleRate, amplitude: 0.4, frequency: 440)
    let audioURL = try writeAudio(samples: samples, sampleRate: sampleRate, prefix: "transcribe-input")
    defer { try? FileManager.default.removeItem(at: audioURL) }

    let output = try await withDependencies {
        $0.defaultAppStorage = appStorage
        $0.logClient = LogClient(
            debug: { _, _ in },
            info: { _, _ in },
            error: { _, _ in },
            dumpDebug: { _, _, _ in },
            logFileURL: { nil }
        )
        $0.mlxClient = MLXClient(
            isModelDownloaded: { _ in true },
            downloadModel: { _, _ in },
            pauseDownload: {},
            cancelDownload: {},
            modelDirectoryURL: { _ in nil },
            deleteModel: { _ in },
            prepareModelIfNeeded: { _ in
                await recorder.append("prepare")
            },
            transcribe: { _, _ in
                await recorder.append("mlx")
                return "ok"
            },
            unloadModel: {}
        )
        $0.audioTrimClient.trimSilence = { url, _ in
            await recorder.append("trim")
            return url
        }
        $0.audioSpeedClient.speedUp = { url, rate in
            await recorder.append("speed:\(String(format: "%.2f", rate))")
            return url
        }
    } operation: {
        @Shared(.trimSilenceEnabled) var trimEnabled = false
        @Shared(.autoSpeedEnabled) var speedEnabled = false
        $trimEnabled.withLock { $0 = true }
        $speedEnabled.withLock { $0 = true }
        return try await TranscriptionClient.liveValue.transcribe(audioURL, .mini3b, .verbatim, nil)
    }

    #expect(output == "ok")
    let calls = await recorder.snapshot()
    #expect(calls == ["prepare", "trim", "speed:1.10", "mlx"])
}

private actor CallRecorder {
    private var calls: [String] = []

    func append(_ value: String) {
        calls.append(value)
    }

    func snapshot() -> [String] {
        calls
    }
}

private func audioDuration(_ url: URL) throws -> Double {
    let file = try AVAudioFile(forReading: url)
    return Double(file.length) / file.fileFormat.sampleRate
}

private func writeAudio(samples: [Float], sampleRate: Double, prefix: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "\(prefix)-\(UUID().uuidString).wav")

    guard let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: false
    ) else {
        throw AudioFixtureError.invalidFormat
    }

    guard let buffer = AVAudioPCMBuffer(
        pcmFormat: format,
        frameCapacity: AVAudioFrameCount(samples.count)
    ) else {
        throw AudioFixtureError.bufferCreationFailed
    }

    buffer.frameLength = AVAudioFrameCount(samples.count)
    guard let channelData = buffer.floatChannelData?[0] else {
        throw AudioFixtureError.bufferCreationFailed
    }

    for (index, value) in samples.enumerated() {
        channelData[index] = value
    }

    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
    return url
}

private func makeSineWave(count: Int, sampleRate: Double, amplitude: Float, frequency: Double) -> [Float] {
    (0..<count).map { index in
        let time = Double(index) / sampleRate
        return amplitude * Float(sin(2 * .pi * frequency * time))
    }
}

private enum AudioFixtureError: Error {
    case invalidFormat
    case bufferCreationFailed
}
