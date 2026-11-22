import Foundation

// Chat models can answer dictated questions unless the instructions identify the transcript.
public enum CloudPromptTranscript {
    public static let tag = "<transcript>"
    public static let closingTag = "</transcript>"
    public static let sentence = "The user message holds the transcript inside \(tag) tags."

    public static func isMentioned(in prompt: String) -> Bool {
        prompt.contains(tag)
    }

    public static func instructions(for prompt: String) -> [String] {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [sentence] }
        return isMentioned(in: trimmed) ? [trimmed] : [trimmed, sentence]
    }
}
