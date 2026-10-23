import CoreGraphics

/// One rendered instant of the liquid capsule, in points of the stage.
struct LiquidCapsuleFrame: Equatable, Sendable {
    var pill: Blob
    var secondary: Blob
    var contentOpacity: Double
    var contentBlur: Double
    var secondaryOpacity: Double
    var secondaryBlur: Double
    var ripple: Ripple?
    var glow: SIMD3<Double>
    var visibility: Double
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

    static let hidden = LiquidCapsuleFrame(
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
