import SwiftUI

struct CloudModelRow: View {
    let title: String
    var subtitle = ""
    var isMonospaced = true
    var symbol: String?
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbol {
                    Image(systemName: symbol)
                        .foregroundStyle(Color.accentColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(isMonospaced ? .caption.monospaced() : .caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: .rect(cornerRadius: 7))
            .contentShape(.rect(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var background: Color {
        if isSelected { return Color.accentColor.opacity(0.14) }
        return isHovering ? Color.primary.opacity(0.06) : .clear
    }
}

#Preview {
    VStack(spacing: 2) {
        CloudModelRow(title: "GPT-6 Luna", subtitle: "gpt-6-luna · Fastest", isSelected: true) {}
        CloudModelRow(title: "gpt-5.5", isSelected: false) {}
        CloudModelRow(title: "Use “my-model”", subtitle: "Any model ID that the provider accepts", isMonospaced: false, symbol: "plus.circle", isSelected: false) {}
    }
    .frame(width: 380)
    .padding()
}
