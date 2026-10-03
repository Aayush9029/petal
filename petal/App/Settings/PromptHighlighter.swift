import AppKit
import CloudCleanupFeature

@MainActor
enum PromptHighlighter {
    static let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    static let boldFont = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)

    static var baseAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2.5
        return [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
    }

    static func apply(to textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: fullRange)
        for token in CloudPromptToken.scan(storage.string) {
            storage.addAttributes(attributes(for: token.kind), range: token.range)
        }
        storage.endEditing()
        textView.typingAttributes = baseAttributes
    }

    private static func attributes(for kind: CloudPromptToken.Kind) -> [NSAttributedString.Key: Any] {
        switch kind {
        case .tag:
            [.font: boldFont, .foregroundColor: NSColor.systemPink]
        case .variable:
            [
                .font: boldFont,
                .foregroundColor: NSColor.controlAccentColor,
                .backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.12),
            ]
        case .unknownVariable:
            [
                .foregroundColor: NSColor.systemRed,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .underlineColor: NSColor.systemRed,
            ]
        }
    }
}
