import Shared
import SwiftUI

/// Namespace shared by every phase's glass so Liquid Glass can morph the
/// capsule between statuses instead of hard-swapping separate surfaces.
/// Injected by ``FloatingCapsuleView`` on macOS 26+; `nil` otherwise.
private struct GlassCapsuleNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var glassCapsuleNamespace: Namespace.ID? {
        get { self[GlassCapsuleNamespaceKey.self] }
        set { self[GlassCapsuleNamespaceKey.self] = newValue }
    }
}

private struct FloatingCapsuleChrome: ViewModifier {
    private static let contentWidth: CGFloat = 150

    var blur: CGFloat
    var highlight: Color?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.glassCapsuleNamespace) private var glassNamespace
    @Shared(.floatingCapsuleBackgroundStyle) private var backgroundStyle

    /// Every status renders one capsule that carries this identity, so the
    /// glass matched-geometry morphs from status to status.
    private static let glassID = "petal.floatingCapsule"

    private var strokeColor: Color {
        colorScheme == .dark ? .white.opacity(0.10) : .black.opacity(0.08)
    }

    private var solidColor: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.97)
    }

    func body(content: Content) -> some View {
        let padded = content
            .blur(radius: blur)
            .frame(width: Self.contentWidth, height: 18)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
        background(
            padded.background {
                if let highlight {
                    Capsule().fill(highlight)
                }
            }
        )
    }

    @ViewBuilder
    private func background(_ view: some View) -> some View {
        let stroke = Capsule().strokeBorder(strokeColor, lineWidth: 1)
        if #available(macOS 26.0, *) {
            switch backgroundStyle {
            case .liquidGlass:
                liquidGlass(view).overlay { stroke }
            case .solid:
                view.background { Capsule().fill(solidColor) }.overlay { stroke }
            }
        } else {
            switch backgroundStyle {
            case .liquidGlass:
                // Liquid Glass is unavailable before macOS 26; fall back to a
                // translucent NSVisualEffectView rather than a flat color.
                view
                    .background { CapsuleVisualEffectBackground().clipShape(Capsule()) }
                    .overlay { stroke }
            case .solid:
                view.background { Capsule().fill(solidColor) }.overlay { stroke }
            }
        }
    }

    /// Native Liquid Glass. When the parent supplies a namespace, tag the glass
    /// with a stable id so status changes morph the single capsule fluidly
    /// (matched-geometry) rather than fading one surface out and another in.
    @available(macOS 26.0, *)
    @ViewBuilder
    private func liquidGlass(_ view: some View) -> some View {
        if let glassNamespace {
            view
                .glassEffect(in: Capsule())
                .glassEffectID(Self.glassID, in: glassNamespace)
        } else {
            view.glassEffect(in: Capsule())
        }
    }
}

extension View {
    func floatingCapsuleChrome(blur: CGFloat = 0, highlight: Color? = nil) -> some View {
        modifier(FloatingCapsuleChrome(blur: blur, highlight: highlight))
    }
}
