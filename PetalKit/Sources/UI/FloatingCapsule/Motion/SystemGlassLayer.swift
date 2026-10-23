import SwiftUI

/// Draws the blobs of one frame with system Liquid Glass. The glass effect
/// container blends the shapes where they come close, so the stop drop pulls
/// a liquid neck out of the pill and merges back into it.
@available(macOS 26.0, *)
struct SystemGlassLayer: View {
    let frame: CapsuleFrame
    let size: CGSize
    var caustic = SIMD2<Double>.zero

    @Namespace private var namespace

    private static let library = ShaderLibrary.bundle(.module)
    /// Below the settled gap, so the split pair separates once it settles.
    private static let mergeSpacing: CGFloat = 6

    var body: some View {
        ZStack(alignment: .topLeading) {
            diffusionHalo(frame.pill)
            stopHalo(frame.secondary)

            GlassEffectContainer(spacing: Self.mergeSpacing) {
                ZStack(alignment: .topLeading) {
                    glass(frame.pill, tint: .white.opacity(0.10 * frame.diffusion + 0.14 * frame.transcribeHover))
                        .glassEffectID("pill", in: namespace)

                    if frame.secondary.size.width > 0 {
                        glass(frame.secondary, tint: .red.opacity(0.42 * frame.stopHover))
                            .glassEffectID("secondary", in: namespace)
                            .glassEffectUnion(id: frame.isDismissing ? "pill" : "secondary", namespace: namespace)
                            .glassEffectTransition(.matchedGeometry)
                    }
                }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
            }

            Rectangle()
                .fill(.black)
                .frame(width: size.width, height: size.height)
                .colorEffect(glints)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .opacity(frame.visibility)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func glass(_ blob: CapsuleFrame.Blob, tint: Color) -> some View {
        Color.clear
            .frame(width: max(blob.size.width, 0), height: max(blob.size.height, 0))
            .glassEffect(.regular.tint(tint), in: Squircle())
            .position(blob.center)
    }

    /// A soft glow that spreads past the glass edge while the drop forms, pulses, or leaves.
    @ViewBuilder
    private func diffusionHalo(_ blob: CapsuleFrame.Blob) -> some View {
        if frame.diffusion > 0.01 {
            Squircle()
                .fill(.white.opacity(0.22 * frame.diffusion))
                .frame(
                    width: blob.size.width + 10 * frame.diffusion,
                    height: blob.size.height + 10 * frame.diffusion
                )
                .blur(radius: 4 + 8 * frame.diffusion)
                .position(blob.center)
        }
    }

    /// A soft red bloom that spreads from the stop drop while the pointer is over it.
    @ViewBuilder
    private func stopHalo(_ blob: CapsuleFrame.Blob) -> some View {
        if frame.stopHover > 0.01, blob.size.width > 0 {
            Squircle()
                .fill(.red.opacity(0.35 * frame.stopHover))
                .frame(width: blob.size.width + 8, height: blob.size.height + 8)
                .blur(radius: 9)
                .position(blob.center)
        }
    }

    private var glints: Shader {
        let scale = Float(CapsuleChoreography.shaderScale)
        return Self.library.petalGlassGlints(
            Self.shape(frame.pill),
            Self.shape(frame.secondary),
            .float4(scale, 20 * scale, Float(1 - 0.6 * frame.diffusion), 0),
            .float2(Float(caustic.x), Float(caustic.y))
        )
    }

    private static func shape(_ blob: CapsuleFrame.Blob) -> Shader.Argument {
        .float4(
            Float(blob.center.x),
            Float(blob.center.y),
            Float(blob.size.width / 2),
            Float(blob.size.height / 2)
        )
    }
}
