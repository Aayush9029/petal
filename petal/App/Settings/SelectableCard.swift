import SwiftUI
import UI

/// Selection inverts the card instead of washing it in the accent color, which would fight the live previews the cards carry.
struct SelectableCard<Content: View>: View {
    private static var cornerRadius: CGFloat { 10 }

    let isSelected: Bool
    var isBlack = false
    let action: () -> Void
    @ViewBuilder let content: Content

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            content
                .foregroundStyle(isSelected ? AnyShapeStyle(selectedForeground) : AnyShapeStyle(.primary))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
                .background(cardBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                        .strokeBorder(
                            isSelected ? selectedFill : .primary.opacity(isHovering ? 0.18 : 0.08),
                            lineWidth: isSelected ? 2 : 1
                        )
                }
                .contentShape(.rect(cornerRadius: Self.cornerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { isHovering = $0 }
    }

    private var selectedFill: Color {
        colorScheme == .dark ? .white : .black
    }

    private var selectedForeground: Color {
        colorScheme == .dark ? .black : .white
    }

    @ViewBuilder
    private var cardBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(selectedFill)
        } else if isBlack {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(.black.opacity(colorScheme == .dark ? 0.35 : 0.06))
        } else {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
    }
}
