import SwiftUI

/// Shows a fixed shortcut, such as a two-step chord, as key caps.
struct KeyCapsLabel: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.callout.weight(.medium).monospaced())
                    .padding(.horizontal, 7)
                    .frame(height: 24)
                    .background(Color.primary.opacity(0.07), in: .rect(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                    }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    KeyCapsLabel(keys: ["⌃X", "⌃S"])
        .padding()
}
