import Foundation
import Testing
@testable import AudioClient

struct AudioCapturePreparationTests {
    private func configuration(
        input: String = AudioInputDevice.systemDefaultID,
        defaultUID: String? = "built-in",
        streaming: Bool = false
    ) -> AudioCaptureConfiguration {
        AudioCaptureConfiguration(inputDeviceID: input, defaultInputUID: defaultUID, streaming: streaming)
    }

    @Test
    func changingTheSystemInputInvalidatesThePreparedRecorder() {
        let cached = configuration()
        #expect(cached.canReuse(for: cached, captureDeviceID: nil))
        #expect(!cached.canReuse(for: configuration(defaultUID: "usb"), captureDeviceID: nil))
        #expect(!configuration(defaultUID: nil).canReuse(for: configuration(defaultUID: nil), captureDeviceID: nil))
    }

    @Test
    func anExplicitInputIsIndependentOfTheSystemDefaultButMustStillMatchAndBeConnected() {
        let cached = configuration(input: "usb")
        let requested = configuration(input: "usb", defaultUID: "headset")
        #expect(cached.canReuse(for: requested, captureDeviceID: "usb"))
        #expect(!cached.canReuse(for: requested, captureDeviceID: "usb", captureDeviceIsConnected: false))
        #expect(!cached.canReuse(for: requested, captureDeviceID: "built-in"))
        #expect(!cached.canReuse(for: configuration(input: "headset"), captureDeviceID: "usb"))
        #expect(!cached.canReuse(for: configuration(), captureDeviceID: "usb"))
    }

    @Test
    func switchingStreamingModeRequiresANewPreparation() {
        let cached = configuration(streaming: true)
        #expect(cached.canReuse(for: cached, captureDeviceID: "built-in"))
        #expect(!cached.canReuse(for: cached, captureDeviceID: nil))
        #expect(!cached.canReuse(for: configuration(), captureDeviceID: "built-in"))
        #expect(!configuration().canReuse(for: cached, captureDeviceID: nil))
    }

    @Test
    func aFailedPreparedSessionGetsAFreshStreamWithoutLeakingItsAudio() async throws {
        var attempts = 0
        let pendingStream = try AudioRecordingStartup.start(streaming: true) { producer in
            let producer = try #require(producer)
            attempts += 1
            if attempts == 1 {
                producer.append([Float](repeating: 1, count: 1600))
                producer.finish(throwing: CancellationError())
                throw PreparedCaptureStartFailure.unavailable
            }
            producer.append([2, 3, 4])
            producer.finish()
        }
        let stream = try #require(pendingStream)

        var samples: [Float] = []
        for try await chunk in stream { samples.append(contentsOf: chunk) }
        #expect(attempts == 2)
        #expect(samples == [2, 3, 4])
    }

    @Test
    func fileRecordingCanRetryWithoutCreatingAStream() throws {
        var attempts = 0
        let stream = try AudioRecordingStartup.start(streaming: false) { producer in
            #expect(producer == nil)
            attempts += 1
            if attempts == 1 { throw PreparedCaptureStartFailure.unavailable }
        }
        #expect(attempts == 2)
        #expect(stream == nil)
    }

    @Test
    func ordinaryErrorsAreNotRetriedAndPreparedRecoveryIsBounded() {
        var attempts = 0
        #expect(throws: TestFailure.unavailable) {
            try AudioRecordingStartup.start(streaming: true) { _ in
                attempts += 1
                throw TestFailure.unavailable
            }
        }
        #expect(attempts == 1)

        attempts = 0
        #expect(throws: PreparedCaptureStartFailure.self) {
            try AudioRecordingStartup.start(streaming: true) { _ in
                attempts += 1
                throw PreparedCaptureStartFailure.unavailable
            }
        }
        #expect(attempts == 2)
    }

    private enum TestFailure: Error, Equatable {
        case unavailable
    }
}
