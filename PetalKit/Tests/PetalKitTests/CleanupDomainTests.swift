import Dependencies
import Foundation
@testable import LocalCleanupClient
@testable import Shared
import Testing

@Test
func petalW1PromptMatchesQwen3NonThinkingLayout() {
    let text = LocalCleanupPrompt.text(transcript: "um hi")
    #expect(text.hasPrefix("<|im_start|>system\n\(LocalCleanupPrompt.petalW1System)<|im_end|>"))
    #expect(text.hasSuffix("<|im_start|>user\num hi<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n"))
    #expect(LocalCleanupPrompt.maxOutputTokens(promptTokens: 100) == 162)
}

@Test
func retiredS1MiniSettingsAreRemoved() {
    let store = UserDefaults(suiteName: UUID().uuidString)!
    store.set("formal", forKey: "s1_mini_styling")
    store.set("Prompt", forKey: "s1_mini_system_prompt")
    store.set("cloud", forKey: "cleanup_model")
    withDependencies {
        $0.defaultAppStorage = store
    } operation: {
        CleanupModel.removeRetiredSettings()
    }
    #expect(store.string(forKey: "s1_mini_styling") == nil)
    #expect(store.string(forKey: "s1_mini_system_prompt") == nil)
    #expect(store.string(forKey: "cleanup_model") == "cloud")
}

@Test
func retiredS1MiniSelectionMovesToPetalW1() {
    #expect(CleanupModel(rawValue: "s1-mini") == .petalW1)
    #expect(CleanupModel.allCases.map(\.rawValue) == ["off", "apple-intelligence", "petal-w1", "cloud"])
}

@Test(arguments: [
    (appleIntelligence: true, mode: "smart", expected: CleanupModel.appleIntelligence),
    (appleIntelligence: true, mode: "verbatim", expected: .off),
    (appleIntelligence: false, mode: "smart", expected: .off),
])
func legacyAppleIntelligenceSettingMigrates(appleIntelligence: Bool, mode: String, expected: CleanupModel) {
    let store = UserDefaults(suiteName: UUID().uuidString)!
    store.set(appleIntelligence, forKey: "apple_intelligence_enabled")
    store.set(mode, forKey: "transcription_mode")
    withDependencies {
        $0.defaultAppStorage = store
    } operation: {
        #expect(CleanupModel.legacyDefault == expected)
    }
}

@Test
func fillerOnlyDetection() {
    #expect(FillerWords.isFillerOnly("um"))
    #expect(FillerWords.isFillerOnly("Uh, hmm... um."))
    #expect(!FillerWords.isFillerOnly("um yes"))
    #expect(!FillerWords.isFillerOnly(""))
}

private func wordCount(_ text: String) -> Int { text.split(whereSeparator: \.isWhitespace).count }

@Test
func shortTranscriptIsOneChunk() {
    #expect(CleanupChunker(maxTokens: 10).chunks("  one two three  ", tokenCount: wordCount) == ["one two three"])
    #expect(CleanupChunker(maxTokens: 10).chunks("   ", tokenCount: wordCount).isEmpty)
}

@Test
func longTranscriptSplitsAtSentenceEnds() {
    let text = "One two three four. Five six seven eight. Nine ten eleven twelve."
    let chunks = CleanupChunker(maxTokens: 8).chunks(text, tokenCount: wordCount)
    #expect(chunks == ["One two three four. Five six seven eight.", "Nine ten eleven twelve."])
}

@Test
func unpunctuatedTranscriptSplitsAtWords() {
    let words = (1 ... 25).map { "w\($0)" }
    let chunks = CleanupChunker(maxTokens: 10).chunks(words.joined(separator: " "), tokenCount: wordCount)
    #expect(chunks.count == 3)
    #expect(chunks.allSatisfy { wordCount($0) <= 10 })
    #expect(chunks.joined(separator: " ") == words.joined(separator: " "))
}

@Test
func chunkOutputsJoinByLayout() {
    #expect(CleanupChunker.join(["First.", "", "Second."]) == "First. Second.")
    #expect(CleanupChunker.join(["Hi Sam,\n\nBody.", "Thanks,\nJo"]) == "Hi Sam,\n\nBody.\n\nThanks,\nJo")
}

@Test
func emptyOutputIsTrustedOnlyForShortChunks() {
    #expect(CleanupChunker.canBeFillerOnly("um uh"))
    #expect(!CleanupChunker.canBeFillerOnly(String(repeating: "word ", count: 20)))
}
