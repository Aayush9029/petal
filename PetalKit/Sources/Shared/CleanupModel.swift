import CasePaths
import Dependencies
import Foundation

@CasePathable
public enum CleanupModel: String, CaseIterable, Identifiable, Sendable, Codable {
    case off
    case appleIntelligence = "apple-intelligence"
    case petalW1 = "petal-w1"
    case s1Mini = "s1-mini"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .off: "Off"
        case .appleIntelligence: "Apple Intelligence"
        case .s1Mini: "S1-mini"
        case .petalW1: "Petal W1"
        }
    }

    public var summary: String? {
        switch self {
        case .off: nil
        case .appleIntelligence: "Rewrites with your own instructions."
        case .s1Mini: "Removes fillers and formats numbers and dates."
        case .petalW1: "Condenses rambles and repeats, keeps your voice."
        }
    }

    /// Runs on-device through the local MLX cleanup runtime and needs a one-time download.
    public var isLocal: Bool {
        self == .s1Mini || self == .petalW1
    }

    /// Before the picker existed, cleanup ran only with the Apple Intelligence toggle on and Smart mode selected.
    static var legacyDefault: Self {
        @Dependency(\.defaultAppStorage) var store
        let wasRefining = store.bool(forKey: "apple_intelligence_enabled")
            && store.string(forKey: "transcription_mode") == TranscriptionMode.smart.rawValue
        return wasRefining ? .appleIntelligence : .off
    }
}
