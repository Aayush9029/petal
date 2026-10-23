import SwiftUI

/// Draws the liquid glass of one frame with `LiquidGlass.metal`.
struct LiquidGlassLayer: View {
    let frame: LiquidCapsuleFrame
    let size: CGSize
    var showsRipple = true
    var scale = LiquidCapsuleChoreography.shaderScale

    private static let library = ShaderLibrary.bundle(.module)

    var body: some View {
        Rectangle()
            .fill(.black)
            .frame(width: size.width, height: size.height)
            .colorEffect(shader)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var shader: Shader {
        let scale = Float(scale)
        let ripple = showsRipple ? frame.ripple : nil
        return Self.library.petalLiquidGlass(
            Self.shape(frame.pill),
            Self.shape(frame.secondary),
            .float4(scale, 20 * scale, Float(frame.visibility), Float(frame.secondaryOpacity)),
            .float4(
                Float(ripple?.center.x ?? 0),
                Float(ripple?.center.y ?? 0),
                Float(ripple?.age ?? 0),
                Float(ripple?.strength ?? 0)
            ),
            .float2(Float(ripple?.halfSize.width ?? 0), Float(ripple?.halfSize.height ?? 0)),
            .float4(Float(frame.glow.x), Float(frame.glow.y), Float(frame.glow.z), Float(frame.contentOpacity)),
            .float2(Float(size.width), Float(size.height))
        )
    }

    private static func shape(_ blob: LiquidCapsuleFrame.Blob) -> Shader.Argument {
        .float4(
            Float(blob.center.x),
            Float(blob.center.y),
            Float(blob.size.width / 2),
            Float(blob.size.height / 2)
        )
    }
}
