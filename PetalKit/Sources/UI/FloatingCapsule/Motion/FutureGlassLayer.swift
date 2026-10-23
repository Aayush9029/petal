import SwiftUI

/// Draws the Future glass of one frame with `FutureGlass.metal`.
struct FutureGlassLayer: View {
    let frame: CapsuleFrame
    let size: CGSize
    var showsRipple = true
    var scale = CapsuleChoreography.shaderScale
    var light = CapsuleLight()
    /// Clear droplets for a burst over system glass, dark ones over Future glass.
    var clearDroplets = false

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
        return Self.library.petalFutureGlass(
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
            .float2(Float(size.width), Float(size.height)),
            .float4(Float(light.time), Float(light.level), Float(frame.danger), Float(light.strength)),
            .float2(Float(frame.stopHover), Float(frame.transcribeHover)),
            .float4(Float(light.orbitTurns), Float(light.orbitStrength), light.orbitIsStill ? 1 : 0, 0),
            .float4(Float(frame.burstAge ?? 0), frame.burstAge == nil ? 0 : 1, clearDroplets ? 1 : 0, 0)
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
