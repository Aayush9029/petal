import Assets
import AVFoundation
import Dependencies
import DependenciesMacros
import Foundation
import OSLog

@DependencyClient
public struct SoundClient: Sendable {
    public var warmup: @Sendable () async -> Void = {}
    public var play: @Sendable (SoundEffect) async -> Void = { _ in }
}

extension SoundClient: DependencyKey {
    public static var liveValue: Self {
        let runtime = SoundRuntime()
        return Self(
            warmup: {
                await runtime.warmup()
            },
            play: { effect in await runtime.play(effect) }
        )
    }
}

extension SoundClient: TestDependencyKey {
    public static var testValue: Self {
        Self()
    }
}

public extension DependencyValues {
    var soundClient: SoundClient {
        get { self[SoundClient.self] }
        set { self[SoundClient.self] = newValue }
    }
}

public enum SoundEffect: Sendable {
    case recordingStarted
    case transcriptionStarted
    case transcriptionCompleted
    case transcriptionNoResult
    case welcome
    case refineStarted

    fileprivate var variants: [SoundLibrary] {
        switch self {
        case .recordingStarted: [.start1, .start2, .start3, .start4]
        case .transcriptionStarted: [.prestop]
        case .transcriptionCompleted: [.stop1, .stop2, .stop3, .stop4]
        case .transcriptionNoResult: [.noresult1, .noresult2, .noresult3, .noresult4]
        case .welcome: [.welcome]
        case .refineStarted: [.refine]
        }
    }

    fileprivate var volume: Float {
        switch self {
        case .recordingStarted: 0.3
        case .transcriptionStarted: 0.2
        case .transcriptionCompleted: 0.25
        case .transcriptionNoResult: 0.2
        case .welcome: 0.3
        case .refineStarted: 0.25
        }
    }
}

private actor SoundRuntime {
    private var players: [SoundLibrary: AVAudioPlayer] = [:]

    func warmup() {
        for effect in [SoundEffect.recordingStarted, .transcriptionCompleted] {
            for variant in effect.variants {
                _ = try? player(for: variant)
            }
        }
    }

    func play(_ effect: SoundEffect) {
        let variants = effect.variants
        let variant = variants[Int.random(in: 0..<variants.count)]
        do {
            let player = try player(for: variant)
            player.volume = effect.volume
            player.currentTime = 0
            player.play()
        } catch {
            Logger(subsystem: "com.optimalapps.petal", category: "SoundClient")
                .error("Could not play sound: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func player(for sound: SoundLibrary) throws -> AVAudioPlayer {
        if let existing = players[sound] {
            return existing
        }
        guard let url = sound.url else {
            throw NSError(
                domain: "SoundClient",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Missing sound resource \(sound.rawValue).m4a"]
            )
        }
        let player = try AVAudioPlayer(contentsOf: url)
        player.prepareToPlay()
        players[sound] = player
        return player
    }
}
