import Shared

enum S1MiniPrompt {
    /// Equals Qwen3's chat template with `enable_thinking=False`. Building it by hand skips a Jinja render per chunk.
    static func text(transcript: String, controls: S1MiniControls) -> String {
        "<|im_start|>system\n\(controls.systemPrompt)<|im_end|>\n<|im_start|>user\n\(controls.controlLine)\n\(transcript)<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n"
    }

    /// The model card's recommended output ceiling.
    static func maxOutputTokens(promptTokens: Int) -> Int {
        Int((Double(promptTokens) * 1.3).rounded(.up)) + 32
    }
}
