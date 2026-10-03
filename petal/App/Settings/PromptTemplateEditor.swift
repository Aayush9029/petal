import Shared
import SwiftUI

struct PromptTemplateEditor: View {
    @Binding var text: String
    let isTranscriptTagMissing: Bool
    let canReset: Bool
    let onAddTranscriptTag: () -> Void
    let onReset: () -> Void
    @State private var insertion: PromptInsertion?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HighlightedPromptTextView(text: $text, insertion: insertion)
                .frame(maxHeight: .infinity)
                .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 10))

            if isTranscriptTagMissing {
                TranscriptTagWarning(onAdd: onAddTranscriptTag)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Insert a variable")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(CloudPromptVariable.allCases) { variable in
                        PromptVariableChip(variable: variable) {
                            insertion = PromptInsertion(text: variable.token)
                        }
                    }
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Petal fills in variables each time it sends your prompt. Your words arrive inside <transcript> tags.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if canReset {
                    SettingsActionButton(title: "Reset", action: onReset)
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var text = "Clean up the dictation.\nSign as {{first_name}}. {{oops}}"
    PromptTemplateEditor(text: $text, isTranscriptTagMissing: true, canReset: true, onAddTranscriptTag: {}, onReset: {})
        .padding()
        .frame(width: 640, height: 520)
}
