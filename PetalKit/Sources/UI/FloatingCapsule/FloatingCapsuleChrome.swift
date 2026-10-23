import SwiftUI

/// Set by ``CapsuleStage``, which draws the glass behind every phase itself.
private struct CapsuleStageDrawsGlassKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var capsuleStageDrawsGlass: Bool {
        get { self[CapsuleStageDrawsGlassKey.self] }
        set { self[CapsuleStageDrawsGlassKey.self] = newValue }
    }
}

private struct FloatingCapsuleChrome: ViewModifier {
    var blur: CGFloat
    var highlight: Color?
    var contentWidth: CGFloat
    var contentHeight: CGFloat
    var horizontalPadding: CGFloat
    var trailingPadding: CGFloat?
    var verticalPadding: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.capsuleStageDrawsGlass) private var stageDrawsGlass

    private var strokeColor: Color {
        colorScheme == .dark ? .white.opacity(0.10) : .black.opacity(0.08)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        let padded = content
            .blur(radius: blur)
            .frame(width: contentWidth, height: contentHeight, alignment: .center)
            .padding(.leading, horizontalPadding)
            .padding(.trailing, trailingPadding ?? horizontalPadding)
            .padding(.vertical, verticalPadding)
        if stageDrawsGlass {
            padded
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background {
                    if let highlight {
                        Squircle().fill(highlight)
                    }
                }
        } else {
            // Liquid Glass is unavailable before macOS 26; a translucent
            // NSVisualEffectView stands in for it.
            padded
                .background {
                    if let highlight {
                        Capsule().fill(highlight)
                    }
                }
                .background { CapsuleVisualEffectBackground().clipShape(Capsule()) }
                .overlay { Capsule().strokeBorder(strokeColor, lineWidth: 1) }
        }
    }
}

extension View {
    func floatingCapsuleChrome(
        blur: CGFloat = 0,
        highlight: Color? = nil,
        contentWidth: CGFloat = 150,
        contentHeight: CGFloat = 20,
        horizontalPadding: CGFloat = 16,
        trailingPadding: CGFloat? = nil,
        verticalPadding: CGFloat = 11
    ) -> some View {
        modifier(FloatingCapsuleChrome(
            blur: blur,
            highlight: highlight,
            contentWidth: contentWidth,
            contentHeight: contentHeight,
            horizontalPadding: horizontalPadding,
            trailingPadding: trailingPadding,
            verticalPadding: verticalPadding
        ))
    }
}
