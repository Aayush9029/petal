import SwiftUI
import UI

struct S1MiniStylePreview: View {
    let input: String
    let output: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            line(title: "You say", text: input)
                .foregroundStyle(.secondary)
            line(title: "Petal writes", text: output)
                .animatedIntelligenceGradient()
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.15), value: output)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 10))
    }

    private func line(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    S1MiniStylePreview(
        input: "hmm im gonna be late theres a cute dog outside i cant just walk past him",
        output: "I'm going to be late. There's a cute dog outside. I can't just walk past him."
    )
    .padding()
    .frame(width: 500)
}
