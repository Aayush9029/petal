import Dependencies
import DependenciesMacros
import Foundation
import Shared

enum AudioClientError: LocalizedError, Sendable {
    case notRecording
    case failedToStart
    case invalidStreamFormat
    case streamOverrun

    var errorDescription: String? {
        switch self {
        case .notRecording:
            return "No recording is currently active."
        case .invalidStreamFormat:
            return "The microphone did not provide audio in the format needed for live transcription."
        case .streamOverrun:
            return "Live transcription could not keep up with the microphone."
        case .failedToStart:
            return "Petal could not start recording audio."
        }
    }
}

public struct AudioInputDevice: Identifiable, Hashable, Sendable {
    public static let systemDefaultID = "system-default"
    public static let systemDefault = Self(id: systemDefaultID, name: "Default")

    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

@DependencyClient
public struct AudioClient: Sendable {
    public var isRecording: @Sendable () async -> Bool = { false }
    /// Warmup must leave the microphone inactive.
    public var warmup: @Sendable (_ streaming: Bool) -> Void = { _ in }
    public var availableInputDevices: @Sendable () async -> [AudioInputDevice] = { [] }
    public var startRecording: @Sendable (@escaping @Sendable (Double) -> Void) async throws -> Void
    public var startStreamingRecording: @Sendable (@escaping @Sendable (Double) -> Void) async throws -> AudioSampleStream
    public var stopRecording: @Sendable () async throws -> URL
    public var cancelRecording: @Sendable () async -> Void = {}
    public var unfinishedRecordings: @Sendable () async -> [URL] = { [] }
}

extension AudioClient: DependencyKey {
    public static var liveValue: Self {
        return Self(
            isRecording: {
                await LiveAudioCaptureRuntime.shared.isRecording()
            },
            warmup: { streaming in
                LiveAudioCaptureRuntime.shared.warmup(streaming: streaming)
            },
            availableInputDevices: {
                LiveAudioCaptureRuntime.availableInputDevices()
            },
            startRecording: { levelHandler in
                try await LiveAudioCaptureRuntime.shared.startRecording(levelHandler: levelHandler)
            },
            startStreamingRecording: { levelHandler in
                try await LiveAudioCaptureRuntime.shared.startStreamingRecording(levelHandler: levelHandler)
            },
            stopRecording: {
                try await LiveAudioCaptureRuntime.shared.stopRecording()
            },
            cancelRecording: {
                await LiveAudioCaptureRuntime.shared.cancelRecording()
            },
            unfinishedRecordings: {
                await LiveAudioCaptureRuntime.shared.unfinishedRecordings()
            }
        )
    }
}

extension AudioClient: TestDependencyKey {
    public static var testValue: Self {
        Self(
            isRecording: { false },
            warmup: { _ in },
            availableInputDevices: { [.systemDefault] },
            startRecording: { _ in },
            startStreamingRecording: { _ in AudioSampleStream { $0.finish() } },
            stopRecording: { URL(fileURLWithPath: "/dev/null") },
            cancelRecording: {},
            unfinishedRecordings: { [] }
        )
    }
}

public extension DependencyValues {
    var audioClient: AudioClient {
        get { self[AudioClient.self] }
        set { self[AudioClient.self] = newValue }
    }
}
