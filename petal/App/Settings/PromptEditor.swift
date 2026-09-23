import SwiftUI

struct PromptEditor: View {
    @Binding var text: String
    let defaultText: String
    var minHeight: CGFloat = 180
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $text)
                .font(.callout)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: minHeight)
                .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 10))

            HStack {
                if let note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
    @Previewable @State var text = "Custom prompt"
    PromptEditor(text: $text, defaultText: "Default prompt", note: "Other wording can lower quality.")
        .frame(width: 500)
}
