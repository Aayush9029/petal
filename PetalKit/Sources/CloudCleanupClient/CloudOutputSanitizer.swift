import Foundation
import Shared

enum CloudOutputSanitizer {
    static func clean(_ output: String) -> String {
        var text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix(CloudPromptTranscript.tag), text.hasSuffix(CloudPromptTranscript.closingTag) {
            text = String(text.dropFirst(CloudPromptTranscript.tag.count).dropLast(CloudPromptTranscript.closingTag.count))
        }
        text = text.replacing(/[ ]?\(\[[^\]\n]+\]\(https?:\/\/[^)\s]+\)\)/, with: "")
        text = text.replacing(/[ ]?\[[A-Za-z0-9.-]+\.[A-Za-z]{2,}\]\(https?:\/\/[^)\s]+\)/, with: "")
        return text
            .replacing(/[ \t]+$/.anchorsMatchLineEndings(), with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
