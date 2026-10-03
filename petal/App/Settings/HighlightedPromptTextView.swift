import AppKit
import CloudCleanupFeature
import SwiftUI

struct HighlightedPromptTextView: NSViewRepresentable {
    @Binding var text: String
    var insertion: PromptInsertion?
    var isEditable = true

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isEditable = isEditable
        textView.isSelectable = isEditable
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textContainerInset = NSSize(width: 6, height: 10)
        textView.string = text
        PromptHighlighter.apply(to: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
            PromptHighlighter.apply(to: textView)
        }
        if let insertion, insertion.id != context.coordinator.lastInsertionID {
            context.coordinator.lastInsertionID = insertion.id
            textView.window?.makeFirstResponder(textView)
            textView.insertText(insertion.text, replacementRange: textView.selectedRange())
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var lastInsertionID: UUID?

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            PromptHighlighter.apply(to: textView)
            text.wrappedValue = textView.string
        }
    }
}
