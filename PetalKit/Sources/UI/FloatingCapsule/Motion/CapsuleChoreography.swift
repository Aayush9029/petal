import CoreGraphics
import Foundation

enum CapsuleChoreography {
    static let stageSize = CGSize(width: 440, height: 150)
    static let pillHeight: CGFloat = 50
    static let bottomInset: CGFloat = 44
    static let restCenter = CGPoint(x: stageSize.width / 2, y: stageSize.height - bottomInset - pillHeight / 2)
    static let secondarySize = CGSize(width: 52, height: 49)
    static let gap: CGFloat = 7
    static let tuckedScale: CGFloat = 0.5
    static let riseDistance: CGFloat = 30
    static let liftDistance: CGFloat = 38
    // The shader is calibrated for a 98-point pill.
    static let shaderScale = pillHeight / 98

    static let dismissDuration = 0.55
    static let burstDuration = 0.5
    static let orbitTurnsPerSecond = 0.85
    static let orbitRamp = 0.7
    static let reducedMotionFade = 0.15
    static let settleDuration = 3.2
    static let appearRippleDelay = 0.15

    static func dismissDuration(reduceMotion: Bool) -> Double {
        reduceMotion ? reducedMotionFade : dismissDuration
    }

    static func criticallyDamped(_ t: Double, omega: Double) -> Double {
        guard t > 0 else { return 0 }
        let x = omega * t
        return 1 - (1 + x) * exp(-x)
    }

    static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = clamp((x - edge0) / (edge1 - edge0))
        return t * t * (3 - 2 * t)
    }

    static func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }

    // Smooth the knee to avoid a velocity jump at zero.
    static func smoothMax(_ x: Double, knee: Double = 0.05) -> Double {
        0.5 * (x + (x * x + knee * knee).squareRoot()) - 0.5 * knee
    }
}

struct CapsuleSpring: Equatable, Sendable {
    var from: Double
    var to: Double
    var start: Double
    var omega: Double

    init(_ value: Double, omega: Double) {
        from = value
        to = value
        start = -.infinity
        self.omega = omega
    }

    func value(at time: Double) -> Double {
        from + (to - from) * CapsuleChoreography.criticallyDamped(time - start, omega: omega)
    }

    mutating func retarget(_ target: Double, at time: Double, snap: Bool = false) {
        guard target != to || snap else { return }
        from = snap ? target : value(at: time)
        to = target
        start = time
    }
}
