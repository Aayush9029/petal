import Shared
import SwiftUI

private struct FloatingCapsuleChrome: ViewModifier {
    var blur: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @Shared(.floatingCapsuleBackgroundStyle) private var backgroundStyle

    private var strokeColor: Color {
        colorScheme == .dark ? .white.opacity(0.10) : .black.opacity(0.08)
    }

    private var solidColor: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.97)
    }

    func body(content: Content) -> some View {
        let padded = content
            .blur(radius: blur)
            .frame(height: 18)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
        background(padded)
    }

    @ViewBuilder
    private func background(_ view: some View) -> some View {
        let stroke = Capsule().strokeBorder(strokeColor, lineWidth: 1)
        if #available(macOS 26.0, *) {
            switch backgroundStyle {
            case .liquidGlass:
                view.glassEffect(in: Capsule()).overlay { stroke }
            case .solid:
                view.background { Capsule().fill(solidColor) }.overlay { stroke }
            }
        } else {
            // Liquid Glass is unavailable before macOS 26; fall back to a
            // translucent NSVisualEffectView rather than a flat color.
            view
                .background { CapsuleVisualEffectBackground().clipShape(Capsule()) }
                .overlay { stroke }
        }
    }
}

extension View {
    func floatingCapsuleChrome(blur: CGFloat = 0) -> some View {
        modifier(FloatingCapsuleChrome(blur: blur))
    }
}
