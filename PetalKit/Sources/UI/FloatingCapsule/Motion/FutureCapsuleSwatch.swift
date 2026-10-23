import SwiftUI

/// A still Future capsule behind arbitrary content, for previews of the style.
public struct FutureCapsuleSwatch<Content: View>: View {
    private let content: Content
    private let margin: CGFloat = 12

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .environment(\.colorScheme, .dark)
            .background {
                GeometryReader { proxy in
                    let canvas = CGSize(width: proxy.size.width + 2 * margin, height: proxy.size.height + 2 * margin)
                    FutureGlassLayer(
                        frame: .still(pill: .init(
                            center: CGPoint(x: canvas.width / 2, y: canvas.height / 2),
                            size: proxy.size
                        )),
                        size: canvas,
                        showsRipple: false,
                        scale: proxy.size.height / 98
                    )
                    .offset(x: -margin, y: -margin)
                }
            }
    }
}

extension CapsuleFrame {
    static func still(pill: Blob) -> Self {
        CapsuleFrame(
            pill: pill,
            secondary: .zero,
            contentOpacity: 1,
            contentBlur: 0,
            secondaryOpacity: 0,
            secondaryBlur: 0,
            ripple: nil,
            glow: FloatingCapsuleState.Phase.recording.capsuleGlow,
            visibility: 1,
            isSplit: false,
            isVisible: true
        )
    }
}
