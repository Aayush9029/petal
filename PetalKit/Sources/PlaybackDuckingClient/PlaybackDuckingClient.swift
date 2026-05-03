import AudioToolbox
import CoreAudio
import Dependencies
import DependenciesMacros
import Foundation
import os

public enum PlaybackDuckingError: LocalizedError, Sendable {
    case defaultOutputDeviceUnavailable
    case volumeUnavailable
    case volumeNotWritable
    case coreAudio(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .defaultOutputDeviceUnavailable:
            "Default output device is unavailable."
        case .volumeUnavailable:
            "Output volume is unavailable."
        case .volumeNotWritable:
            "Output volume cannot be changed."
        case let .coreAudio(status):
            "CoreAudio volume operation failed with status \(status)."
        }
    }
}

@DependencyClient
public struct PlaybackDuckingClient: Sendable {
    public var startDucking: @Sendable () async throws -> Void
    public var stopDucking: @Sendable () async -> Void = {}
}

extension PlaybackDuckingClient: DependencyKey {
    public static var liveValue: Self {
        Self(
            startDucking: {
                try await LivePlaybackDuckingRuntimeContainer.shared.startDucking()
            },
            stopDucking: {
                await LivePlaybackDuckingRuntimeContainer.shared.stopDucking()
            }
        )
    }
}

extension PlaybackDuckingClient: TestDependencyKey {
    public static var testValue: Self {
        Self(
            startDucking: {},
            stopDucking: {}
        )
    }
}

public extension DependencyValues {
    var playbackDuckingClient: PlaybackDuckingClient {
        get { self[PlaybackDuckingClient.self] }
        set { self[PlaybackDuckingClient.self] = newValue }
    }
}

private actor LivePlaybackDuckingRuntime {
    private let logger = Logger(subsystem: "com.optimalapps.petal", category: "PlaybackDuckingClient")
    private var restoreState: RestoreState?

    func startDucking() throws {
        guard restoreState == nil else { return }

        let deviceID = try defaultOutputDeviceID()
        let volume = try outputVolume(deviceID: deviceID)
        try setOutputVolume(max(0, min(1, volume * 0.5)), deviceID: deviceID)
        restoreState = RestoreState(deviceID: deviceID, volume: volume)
        logger.debug("System output volume ducked")
    }

    func stopDucking() {
        guard let state = restoreState else { return }
        restoreState = nil

        do {
            try setOutputVolume(state.volume, deviceID: state.deviceID)
            logger.debug("System output volume restored")
        } catch {
            logger.error("Failed to restore system output volume: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func defaultOutputDeviceID() throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr else { throw PlaybackDuckingError.coreAudio(status) }
        guard deviceID != kAudioObjectUnknown else {
            throw PlaybackDuckingError.defaultOutputDeviceUnavailable
        }
        return deviceID
    }

    private func outputVolume(deviceID: AudioDeviceID) throws -> Float32 {
        var address = volumeAddress()
        guard AudioObjectHasProperty(deviceID, &address) else {
            throw PlaybackDuckingError.volumeUnavailable
        }

        var volume = Float32()
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
        guard status == noErr else { throw PlaybackDuckingError.coreAudio(status) }
        return max(0, min(1, volume))
    }

    private func setOutputVolume(_ volume: Float32, deviceID: AudioDeviceID) throws {
        var address = volumeAddress()
        guard AudioObjectHasProperty(deviceID, &address) else {
            throw PlaybackDuckingError.volumeUnavailable
        }

        var isSettable = DarwinBoolean(false)
        let settableStatus = AudioObjectIsPropertySettable(deviceID, &address, &isSettable)
        guard settableStatus == noErr else {
            throw PlaybackDuckingError.coreAudio(settableStatus)
        }
        guard isSettable.boolValue else {
            throw PlaybackDuckingError.volumeNotWritable
        }

        var mutableVolume = max(0, min(1, volume))
        let status = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<Float32>.size),
            &mutableVolume
        )
        guard status == noErr else { throw PlaybackDuckingError.coreAudio(status) }
    }

    private func volumeAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private struct RestoreState {
        var deviceID: AudioDeviceID
        var volume: Float32
    }
}

private enum LivePlaybackDuckingRuntimeContainer {
    static let shared = LivePlaybackDuckingRuntime()
}
