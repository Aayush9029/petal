import Foundation

/// Short replies like "OK" or "wow" gain nothing from cleanup, so they skip the model and paste as said.
public enum CleanupMinimumWords: Int, CaseIterable, Identifiable, Sendable, Codable {
    case any = 1
    case two = 2
    case three = 3
    case five = 5
    case ten = 10

    public var id: Int { rawValue }

    public var displayName: String {
        self == .any ? "Off" : "< \(rawValue) words"
    }

    public func allowsCleanup(of transcript: String) -> Bool {
        FillerWords.isFillerOnly(transcript) || Self.wordCount(transcript) >= rawValue
    }

    public static func wordCount(_ text: String) -> Int {
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            count += 1
        }
        return count
    }
}
