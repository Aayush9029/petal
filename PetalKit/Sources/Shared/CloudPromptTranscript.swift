/// Every system prompt must tell the model where the dictation is, or chat models answer it instead of cleaning it.
public enum CloudPromptTranscript {
    public static let tag = "<transcript>"
    public static let sentence = "The user message holds the transcript inside <transcript> tags."

    public static func isMentioned(in prompt: String) -> Bool {
        prompt.contains(tag)
    }
}
