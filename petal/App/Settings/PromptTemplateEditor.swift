import Shared
import SwiftUI

struct PromptTemplateEditor: View {
    @Binding var text: String
    let defaultText: String
    @State private var insertion: PromptInsertion?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HighlightedPromptTextView(text: $text, insertion: insertion)
                .frame(minHeight: 200)
                .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 8) {
                Text("Insert a variable")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 6)], alignment: .leading, spacing: 6) {
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
                if text != defaultText {
                    SettingsActionButton(title: "Reset") { text = defaultText }
                }
            }
        }
        .padding(14)
    }
}

#Preview {
    @Previewable @State var text = CloudPromptPreset.email.prompt + "\nSign as {{name}}. Today is {{date}}. {{oops}}"
    PromptTemplateEditor(text: $text, defaultText: CloudPromptPreset.email.prompt)
        .frame(width: 500)
}
