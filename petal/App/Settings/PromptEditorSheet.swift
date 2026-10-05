import SwiftUI

struct PromptEditorSheet: View {
    var title = "System Prompt"
    @Binding var text: String
    var showsVariables = true
    let isTranscriptTagMissing: Bool
    let canReset: Bool
    let onAddTranscriptTag: () -> Void
    let onReset: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Divider()

            PromptTemplateEditor(
                text: $text,
                showsVariables: showsVariables,
                isTranscriptTagMissing: isTranscriptTagMissing,
                canReset: canReset,
                onAddTranscriptTag: onAddTranscriptTag,
                onReset: onReset
            )
            .padding(18)
        }
        .frame(minWidth: 620, idealWidth: 680, minHeight: 540, idealHeight: 620)
    }
}

#Preview {
    @Previewable @State var text = "You turn dictation into an email. The user message holds the transcript inside <transcript> tags.\nSign as {{first_name}}."
    PromptEditorSheet(text: $text, isTranscriptTagMissing: false, canReset: true, onAddTranscriptTag: {}, onReset: {}, onDone: {})
}
