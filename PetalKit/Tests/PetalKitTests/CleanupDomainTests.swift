import Dependencies
import Foundation
@testable import S1MiniClient
@testable import Shared
import Testing

@Test
func s1MiniControlLineUsesTrainedTokens() {
    #expect(S1MiniControls().controlLine == "[Styling: semi-formal] [Structure: prose] [Context: general]")
    #expect(
        S1MiniControls(styling: .semiCasual, structure: .lists, context: .email).controlLine
            == "[Styling: semi-casual] [Structure: lists] [Context: email]"
    )
}

@Test
func s1MiniPromptMatchesQwen3NonThinkingLayout() {
    let text = S1MiniPrompt.text(transcript: "um hi", controls: S1MiniControls())
    #expect(text.hasPrefix("<|im_start|>system\nYou are a text normalizer"))
    #expect(text.hasSuffix("[Context: general]\num hi<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n"))
    #expect(S1MiniPrompt.maxOutputTokens(promptTokens: 100) == 162)
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
    #expect(S1MiniChunker(maxTokens: 10).chunks("  one two three  ", tokenCount: wordCount) == ["one two three"])
    #expect(S1MiniChunker(maxTokens: 10).chunks("   ", tokenCount: wordCount).isEmpty)
}

@Test
func longTranscriptSplitsAtSentenceEnds() {
    let text = "One two three four. Five six seven eight. Nine ten eleven twelve."
    let chunks = S1MiniChunker(maxTokens: 8).chunks(text, tokenCount: wordCount)
    #expect(chunks == ["One two three four. Five six seven eight.", "Nine ten eleven twelve."])
}

@Test
func unpunctuatedTranscriptSplitsAtWords() {
    let words = (1 ... 25).map { "w\($0)" }
    let chunks = S1MiniChunker(maxTokens: 10).chunks(words.joined(separator: " "), tokenCount: wordCount)
    #expect(chunks.count == 3)
    #expect(chunks.allSatisfy { wordCount($0) <= 10 })
    #expect(chunks.joined(separator: " ") == words.joined(separator: " "))
}

@Test
func chunkOutputsJoinByLayout() {
    #expect(S1MiniChunker.join(["First.", "", "Second."]) == "First. Second.")
    #expect(S1MiniChunker.join(["Hi Sam,\n\nBody.", "Thanks,\nJo"]) == "Hi Sam,\n\nBody.\n\nThanks,\nJo")
}

@Test
func emptyOutputIsTrustedOnlyForShortChunks() {
    #expect(S1MiniChunker.canBeFillerOnly("um uh"))
    #expect(!S1MiniChunker.canBeFillerOnly(String(repeating: "word ", count: 20)))
}
