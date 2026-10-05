import Shared
import SwiftUI

struct PromptTemplateEditor: View {
    @Binding var text: String
    var showsVariables = true
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

            if showsVariables {
                variables
            }

            HStack(alignment: .firstTextBaseline) {
                Text(footnote)
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

    private var footnote: String {
        showsVariables
            ? "Petal fills in variables each time it sends your prompt. Your words arrive inside <transcript> tags."
            : "Apple Intelligence reads these instructions with each dictation."
    }

    private var variables: some View {
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
    }
}

#Preview {
    @Previewable @State var text = "Clean up the dictation.\nSign as {{first_name}}. {{oops}}"
    PromptTemplateEditor(text: $text, isTranscriptTagMissing: true, canReset: true, onAddTranscriptTag: {}, onReset: {})
        .padding()
        .frame(width: 640, height: 520)
}
