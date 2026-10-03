import SwiftUI

struct PromptPreview: View {
    let text: String
    let onOpen: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onOpen) {
            HighlightedPromptTextView(text: .constant(text), isEditable: false)
                .allowsHitTesting(false)
                .mask {
                    LinearGradient(stops: [.init(color: .black, location: 0.6), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
                }
                .frame(height: 170)
                .background(.quaternary.opacity(isHovering ? 0.9 : 0.6), in: .rect(cornerRadius: 10))
                .overlay(alignment: .bottomTrailing) {
                    Label("Edit", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .frame(height: 22)
                        .background(.regularMaterial, in: .capsule)
                        .padding(8)
                }
                .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.14), value: isHovering)
        .help("Open the prompt editor")
        .accessibilityLabel("Edit System Prompt")
    }
}

#Preview {
    PromptPreview(text: "You turn raw dictation into clean text. The user message holds the transcript inside <transcript> tags.\nSign as {{first_name}}.") {}
        .padding()
        .frame(width: 520)
}
