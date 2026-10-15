import AVFoundation
import Foundation
import Testing
@testable import AudioClient

struct AudioCaptureLifecycleTests {
    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "assets/e2e/conversational_a.wav")
    }

    @Test
    func warmupDoesNotStartRecordingAndRepeatedStartsPreserveAudio() async throws {
        let fixture = fixtureURL
        let runtime = LiveAudioCaptureRuntime(audioFixtureURL: { fixture })
        let expected = try AudioSampleProducer.readFixture(fixture)

        runtime.warmup()
        #expect(!(await runtime.isRecording()))

        for _ in 0..<2 {
            let stream = try await runtime.startStreamingRecording { _ in }
            #expect(await runtime.isRecording())
            let recording = try await runtime.stopRecording()
            defer { try? FileManager.default.removeItem(at: recording) }

            var samples: [Float] = []
            for try await chunk in stream { samples.append(contentsOf: chunk) }
            #expect(samples == expected)
            #expect(!(await runtime.isRecording()))
            #expect(try AVAudioFile(forReading: recording).length > 0)
        }
    }

    @Test
    func cancellationClosesTheStreamAndAllowsTheNextRecording() async throws {
        let fixture = fixtureURL
        let runtime = LiveAudioCaptureRuntime(audioFixtureURL: { fixture })
        let stream = try await runtime.startStreamingRecording { _ in }
        await runtime.cancelRecording()
        #expect(!(await runtime.isRecording()))

        do {
            for try await _ in stream {}
            Issue.record("Cancelling recording must terminate its audio stream with cancellation")
        } catch is CancellationError {}

        try await runtime.startRecording { _ in }
        #expect(await runtime.isRecording())
        await runtime.cancelRecording()
        #expect(!(await runtime.isRecording()))
        #expect(FileManager.default.fileExists(atPath: fixture.path))
    }
}
