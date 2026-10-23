import SwiftUI
import UI

struct SelectableCard<Content: View>: View {
    private static var cornerRadius: CGFloat { 11 }

    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let content: Content

    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            content
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
                .background {
                    if isHovering, !isSelected {
                        cardShape.fill(.primary.opacity(0.05))
                    }
                }
                .settingsSelection(isSelected, in: cardShape)
                .overlay {
                    cardShape.strokeBorder(borderColor, lineWidth: isSelected ? 2 : 1)
                }
                .settingsGlass(in: cardShape)
                .contentShape(.rect(cornerRadius: Self.cornerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { isHovering = $0 }
        .animation(.snappy(duration: 0.2), value: isSelected)
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    private var borderColor: Color {
        if isSelected { return .primary }
        if contrast == .increased { return .primary.opacity(0.55) }
        return .primary.opacity(isHovering ? 0.2 : 0.07)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
    }
}
