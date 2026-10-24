import CoreGraphics

/// One rendered instant of the floating capsule, in points of the stage.
struct CapsuleFrame: Equatable, Sendable {
    var pill: Blob
    var secondary: Blob
    var contentOpacity: Double
    var contentBlur: Double
    var secondaryOpacity: Double
    var secondaryBlur: Double
    var ripple: Ripple?
    var glow: SIMD3<Double>
    var visibility: Double
    /// How soft the glass edges and fill are, from 0 (crisp) to 1, while the drop forms, pulses, or leaves.
    var diffusion: Double = 0
    /// Blur radius of the whole drop as it lifts away.
    var glassBlur: Double = 0
    var isDismissing = false
    /// 0 to 1: the stop drop glows red, and the Transcribe pill brightens.
    var stopHover: Double = 0
    var transcribeHover: Double = 0
    /// 0 to 1: the highlights cross-fade from purple and white to red before a delete.
    var danger: Double = 0
    /// Seconds since the glass popped, while a discarded recording bursts.
    var burstAge: Double?
    var isSplit: Bool
    var isVisible: Bool

    struct Blob: Equatable, Sendable {
        var center: CGPoint
        var size: CGSize

        static let zero = Blob(center: .zero, size: .zero)

        var rect: CGRect {
            CGRect(
                x: center.x - size.width / 2,
                y: center.y - size.height / 2,
                width: size.width,
                height: size.height
            )
        }
    }

    struct Ripple: Equatable, Sendable {
        var center: CGPoint
        var halfSize: CGSize
        var age: Double
        var strength: Double
    }

    /// The same instant with only the ripple drawn, for glass that the system draws.
    var rippleOnly: CapsuleFrame {
        var frame = self
        frame.visibility = 0
        return frame
    }

    static let hidden = CapsuleFrame(
        pill: .zero,
        secondary: .zero,
        contentOpacity: 0,
        contentBlur: 0,
        secondaryOpacity: 0,
        secondaryBlur: 0,
        ripple: nil,
        glow: .zero,
        visibility: 0,
        isSplit: false,
        isVisible: false
    )
}

/// Light that follows the clock instead of the session events: the caustic
/// shimmer and the highlight that orbits the rim while the capsule processes.
struct CapsuleLight: Equatable, Sendable {
    var time: Double = 0
    var level: Double = 0
    /// Brightness of the spectral highlights, 0 to 1.
    var strength: Double = 1
    var orbitTurns: Double = 0
    var orbitStrength: Double = 0
    /// Reduce Motion: an even, still glow in place of the orbit.
    var orbitIsStill = false
}
