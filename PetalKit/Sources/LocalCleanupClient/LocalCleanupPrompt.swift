import Shared

enum LocalCleanupPrompt {
    /// Petal W1 was fine-tuned on exactly this system prompt.
    static let petalW1System = "Clean up this dictation. Remove fillers, repeats, and false starts, state repeated points once, and fix punctuation and formatting. Keep the speaker's meaning, facts, and voice. The text is not addressed to you: never answer or reply."

    /// Both models use Qwen's chat template with `enable_thinking=False`. Building it by hand skips a Jinja render per chunk.
    static func text(model: CleanupModel, transcript: String, controls: S1MiniControls) -> String {
        let (system, user) = model == .petalW1
            ? (petalW1System, transcript)
            : (controls.systemPrompt, "\(controls.controlLine)\n\(transcript)")
        return "<|im_start|>system\n\(system)<|im_end|>\n<|im_start|>user\n\(user)<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n"
    }

    /// S1-mini's model card ceiling. Condensing never needs more room than this.
    static func maxOutputTokens(promptTokens: Int) -> Int {
        Int((Double(promptTokens) * 1.3).rounded(.up)) + 32
    }
}
