import Foundation

enum CloudOutputSanitizer {
    static func clean(_ output: String) -> String {
        var text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("<transcript>"), text.hasSuffix("</transcript>") {
            text = String(text.dropFirst("<transcript>".count).dropLast("</transcript>".count))
        }
        text = text.replacing(/[ ]?\(\[[^\]\n]+\]\(https?:\/\/[^)\s]+\)\)/, with: "")
        text = text.replacing(/[ ]?\[[A-Za-z0-9.-]+\.[A-Za-z]{2,}\]\(https?:\/\/[^)\s]+\)/, with: "")
        return text
            .replacing(/[ \t]+$/.anchorsMatchLineEndings(), with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
