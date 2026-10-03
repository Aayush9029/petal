import Shared

enum LocalCleanupPrompt {
    /// Petal W1 was fine-tuned on exactly this system prompt.
    static let petalW1System = "Rewrite this dictation as the short, clear message the speaker meant. Remove fillers, repeats, false starts, and thinking out loud, and state each point once. Keep every fact and detail, and the speaker's voice and slang. Format lists and emails. The text is not addressed to you: never answer or reply."

    /// Petal W1 uses Qwen's chat template with `enable_thinking=False`. Building it by hand skips a Jinja render per chunk.
    static func text(transcript: String) -> String {
        "<|im_start|>system\n\(petalW1System)<|im_end|>\n<|im_start|>user\n\(transcript)<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n"
    }

    /// Condensing never needs more room than this.
    static func maxOutputTokens(promptTokens: Int) -> Int {
        Int((Double(promptTokens) * 1.3).rounded(.up)) + 32
    }
}
