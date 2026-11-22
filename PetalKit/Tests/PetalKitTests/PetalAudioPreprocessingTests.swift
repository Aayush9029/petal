import AVFoundation
import Dependencies
import Foundation
import LogClient
import MLXClient
import Shared
import Testing
import TranscriptionClient

@Test(arguments: [40, 48])
func fileRecognitionUsesTheAudibleRangeBeforeChoosingASpeed(speechSeconds: Int) async throws {
    let source = try stereoFixture(speechSeconds: speechSeconds, paddingSeconds: 8)
    defer { try? FileManager.default.removeItem(at: source) }
    let generated = LockIsolated<URL?>(nil)
    let stages = LockIsolated<[TranscriptionStage]>([])
    let transcript = try await withDependencies {
        $0.defaultAppStorage = .inMemory
        $0.logClient.debug = { _, _ in }
        $0.mlxClient.transcribe = { url, model in
            #expect(model == .qwen3ASR17B8bit)
            generated.setValue(url)
            let file = try AVAudioFile(forReading: url)
            let rate = speechSeconds == 40 ? 1.0 : 1.1
            #expect(abs(Double(file.length) / file.processingFormat.sampleRate - Double(speechSeconds) / rate) < 0.001)
            #expect(file.processingFormat.channelCount == 2)
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1))
            try file.read(into: buffer)
            let channels = try #require(buffer.floatChannelData)
            #expect(channels[0][0] == 0)
            #expect(channels[1][0] == 0.5)
            return "recognized"
        }
    } operation: {
        @Shared(.trimSilenceEnabled) var trim
        @Shared(.autoSpeedEnabled) var autoSpeed
        $trim.withLock { $0 = true }
        $autoSpeed.withLock { $0 = true }
        return try await TranscriptionClient.liveValue.transcribe(source, .qwen3ASR17B8bit) { stage in
            stages.withValue { $0.append(stage) }
        }
    }
    #expect(transcript == "recognized")
    #expect(stages.value == (speechSeconds == 40 ? [.trimming, .transcribing] : [.trimming, .speeding, .transcribing]))
    let prepared = try #require(generated.value)
    #expect(!FileManager.default.fileExists(atPath: prepared.path))
    #expect(FileManager.default.fileExists(atPath: source.path))
}

@Test
func silentAudioReturnsNoSpeechWithoutCallingARecognizer() async throws {
    let source = try stereoFixture(speechSeconds: 0, paddingSeconds: 1)
    defer { try? FileManager.default.removeItem(at: source) }
    let transcript = try await withDependencies {
        $0.defaultAppStorage = .inMemory
    } operation: {
        try await TranscriptionClient.liveValue.transcribe(source, .qwen3ASR17B8bit)
    }
    #expect(transcript.isEmpty)
}

@Test
func failedRecognitionDiscardsOnlyThePreparedAudio() async throws {
    let source = try stereoFixture(speechSeconds: 1, paddingSeconds: 1)
    defer { try? FileManager.default.removeItem(at: source) }
    let generated = LockIsolated<URL?>(nil)

    await #expect(throws: CancellationError.self) {
        try await withDependencies {
            $0.defaultAppStorage = .inMemory
            $0.logClient.error = { _, _ in }
            $0.mlxClient.transcribe = { url, _ in
                generated.setValue(url)
                throw CancellationError()
            }
        } operation: {
            @Shared(.trimSilenceEnabled) var trim
            $trim.withLock { $0 = true }
            return try await TranscriptionClient.liveValue.transcribe(source, .qwen3ASR17B8bit)
        }
    }
    let prepared = try #require(generated.value)
    #expect(!FileManager.default.fileExists(atPath: prepared.path))
    #expect(FileManager.default.fileExists(atPath: source.path))
}

private func stereoFixture(speechSeconds: Int, paddingSeconds: Int) throws -> URL {
    let sampleRate = 8_000
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 2))
    let frames = UInt32(sampleRate * (paddingSeconds * 2 + speechSeconds))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
    buffer.frameLength = frames
    let channels = try #require(buffer.floatChannelData)
    for frame in 0..<Int(frames) {
        channels[0][frame] = 0
        let second = frame / sampleRate
        channels[1][frame] = (paddingSeconds..<(paddingSeconds + speechSeconds)).contains(second) ? 0.5 : 0
    }
    let url = URL.temporaryDirectory.appending(path: "\(UUID()).wav")
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
    return url
}
