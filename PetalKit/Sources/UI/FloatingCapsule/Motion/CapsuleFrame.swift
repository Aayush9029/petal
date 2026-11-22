import CoreGraphics

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
    var diffusion: Double = 0
    var glassBlur: Double = 0
    var isDismissing = false
    var stopHover: Double = 0
    var transcribeHover: Double = 0
    var danger: Double = 0
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

struct CapsuleLight: Equatable, Sendable {
    var time: Double = 0
    var level: Double = 0
    var strength: Double = 1
    var orbitTurns: Double = 0
    var orbitStrength: Double = 0
    var orbitIsStill = false
}
