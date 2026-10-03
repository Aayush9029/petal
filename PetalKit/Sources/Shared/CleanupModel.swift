import CasePaths
import Dependencies
import Foundation

@CasePathable
public enum CleanupModel: String, CaseIterable, Identifiable, Sendable, Codable {
    case off
    case appleIntelligence = "apple-intelligence"
    case petalW1 = "petal-w1"
    case cloud

    public init?(rawValue: String) {
        switch rawValue {
        case "off": self = .off
        case "apple-intelligence": self = .appleIntelligence
        case "petal-w1", "s1-mini": self = .petalW1
        case "cloud": self = .cloud
        default: return nil
        }
    }

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .off: "Off"
        case .appleIntelligence: "Apple Intelligence"
        case .petalW1: "Petal W1"
        case .cloud: "Cloud Model"
        }
    }

    public var summary: String? {
        switch self {
        case .off: nil
        case .appleIntelligence: "Rewrites with your own instructions."
        case .petalW1: "Condenses rambles and repeats, keeps your voice."
        case .cloud: "OpenAI, Anthropic, or OpenRouter with your own key."
        }
    }

    /// Runs on-device through the local MLX cleanup runtime and needs a one-time download.
    public var isLocal: Bool {
        self == .petalW1
    }

    /// Before the picker existed, cleanup ran only with the Apple Intelligence toggle on and Smart mode selected.
    public static func removeRetiredSettings() {
        @Dependency(\.defaultAppStorage) var store
        for key in ["s1_mini_styling", "s1_mini_structure", "s1_mini_context", "s1_mini_system_prompt"] {
            store.removeObject(forKey: key)
        }
    }

    static var legacyDefault: Self {
        @Dependency(\.defaultAppStorage) var store
        let wasRefining = store.bool(forKey: "apple_intelligence_enabled")
            && store.string(forKey: "transcription_mode") == TranscriptionMode.smart.rawValue
        return wasRefining ? .appleIntelligence : .off
    }
}
