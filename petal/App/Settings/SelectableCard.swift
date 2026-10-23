import SwiftUI
import UI

struct SelectableCard<Content: View>: View {
    private static var cornerRadius: CGFloat { 11 }

    let isSelected: Bool
    var isBlack = false
    var tint = Color.accentColor
    var showsCheckmark = false
    let action: () -> Void
    @ViewBuilder let content: Content

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            content
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
                .background(cardWash)
                .overlay {
                    RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: isSelected ? 2 : 1)
                }
                .overlay(alignment: .topTrailing) {
                    if showsCheckmark, isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                            .padding(5)
                            .transition(.scale.combined(with: .opacity))
                            .accessibilityHidden(true)
                    }
                }
                .settingsGlass(in: cardShape, tint: glassTint)
                .contentShape(.rect(cornerRadius: Self.cornerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { isHovering = $0 }
        .animation(.snappy(duration: 0.2), value: isSelected)
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    private var borderColor: Color {
        if isSelected { return .accentColor }
        if contrast == .increased { return .primary.opacity(0.55) }
        return .primary.opacity(isHovering ? 0.2 : 0.07)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
    }

    private var glassTint: Color {
        if isBlack { return .black.opacity(colorScheme == .dark ? 0.35 : 0.06) }
        return washColor.opacity(isSelected ? 0.2 : 0.06)
    }

    private var cardWash: some View {
        cardShape.fill(
            LinearGradient(
                colors: [washColor.opacity(isSelected ? 0.18 : (isHovering ? 0.1 : 0.06)), washColor.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var washColor: Color {
        isSelected ? .accentColor : tint
    }
}
