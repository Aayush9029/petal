import CoreGraphics
import Foundation

/// The events of one capsule session. Frames are a pure function of these
/// events and the time, so any instant can be rendered or tested on its own.
struct LiquidCapsuleTimeline: Equatable, Sendable {
    private typealias Curve = LiquidCapsuleChoreography

    static let defaultSize = CGSize(width: 198, height: LiquidCapsuleChoreography.pillHeight)

    private(set) var presentedAt: Double?
    private(set) var dismissedAt: Double?
    private(set) var pulseAt: Double?
    private var width = LiquidSpring(defaultSize.width, omega: 11)
    private var height = LiquidSpring(defaultSize.height, omega: 11)
    private var split = LiquidSpring(0, omega: 12)
    private var glowFrom = SIMD3<Double>.zero
    private var glowTo = SIMD3<Double>.zero
    private var glowStart = -Double.infinity
    var reduceMotion = false

    var isPresented: Bool { presentedAt != nil && dismissedAt == nil }

    var lastEventTime: Double {
        [presentedAt, dismissedAt, pulseAt, width.start, height.start, split.start, glowStart]
            .compactMap { $0 }
            .filter(\.isFinite)
            .max() ?? 0
    }

    /// The time after which the frame no longer changes.
    var settledTime: Double {
        if let dismissedAt {
            return dismissedAt + Curve.dismissDuration(reduceMotion: reduceMotion)
        }
        return lastEventTime + Curve.settleDuration
    }

    func isSettled(at time: Double) -> Bool {
        time >= settledTime
    }

    mutating func present(size: CGSize, glow: SIMD3<Double>, at time: Double) {
        presentedAt = time
        dismissedAt = nil
        pulseAt = nil
        width.retarget(size.width, at: time, snap: true)
        height.retarget(size.height, at: time, snap: true)
        split.retarget(0, at: time, snap: true)
        glowFrom = glow
        glowTo = glow
        glowStart = time
    }

    mutating func resize(to size: CGSize, at time: Double) {
        guard let presentedAt, dismissedAt == nil else { return }
        let snap = time - presentedAt < 0.1
        width.retarget(size.width, at: time, snap: snap)
        height.retarget(size.height, at: time, snap: snap)
    }

    mutating func setSplit(_ isSplit: Bool, at time: Double) {
        guard isPresented else { return }
        split.retarget(isSplit ? 1 : 0, at: time)
    }

    mutating func pulse(at time: Double) {
        guard isPresented else { return }
        pulseAt = time
    }

    mutating func setGlow(_ glow: SIMD3<Double>, at time: Double) {
        guard glow != glowTo else { return }
        glowFrom = glowValue(at: time)
        glowTo = glow
        glowStart = time
    }

    mutating func dismiss(at time: Double) {
        guard isPresented else { return }
        dismissedAt = time
    }

    private func glowValue(at time: Double) -> SIMD3<Double> {
        glowFrom + (glowTo - glowFrom) * Curve.smoothstep(0, 0.35, time - glowStart)
    }

    func frame(at time: Double) -> LiquidCapsuleFrame {
        guard let presentedAt, time >= presentedAt else { return .hidden }
        let t = time - presentedAt
        let rest = Curve.restCenter
        let secondarySize = Curve.secondarySize

        let grow = reduceMotion ? 1 : Curve.criticallyDamped(t - 0.02, omega: 10.5)
        let rise = reduceMotion ? 0 : exp(-1.65 * Curve.smoothMax(t - 0.08))
        let targetWidth = reduceMotion ? width.to : width.value(at: time)
        let targetHeight = reduceMotion ? height.to : height.value(at: time)
        let splitValue = reduceMotion ? split.to : split.value(at: time)

        var pillWidth = targetWidth * grow
        var pillHeight = min(pillWidth, targetHeight)
        let pairShift = (secondarySize.width + Curve.gap) / 2
        var pillX = rest.x - pairShift * splitValue
        var y = rest.y + Curve.riseDistance * rise

        let tuckedX = rest.x + targetWidth / 2 - secondarySize.width / 2
        let splitX = rest.x - pairShift + targetWidth / 2 + Curve.gap + secondarySize.width / 2
        var secondaryX = tuckedX + (splitX - tuckedX) * splitValue
        var secondary = split.to > 0 || splitValue > 0.01
            ? CGSize(width: secondarySize.width * grow, height: secondarySize.height * grow)
            : .zero

        if let pulseAt, !reduceMotion, time > pulseAt {
            let age = time - pulseAt
            let wobble = 0.07 * sin(age * 2 * .pi * 2.4) * exp(-age * 5.5)
            pillHeight *= 1 - wobble
            pillWidth *= 1 + 0.4 * wobble
        }

        var contentOpacity = reduceMotion
            ? Curve.smoothstep(0, Curve.reducedMotionFade, t)
            : Curve.smoothstep(0.08, 0.35, t)
        var contentBlur = reduceMotion ? 0 : 7 * (1 - Curve.smoothstep(0.08, 0.40, t))
        var secondaryOpacity = Curve.smoothstep(0.55, 0.95, splitValue)
        var secondaryBlur = reduceMotion ? 0 : 6 * (1 - secondaryOpacity)
        var visibility = reduceMotion ? Curve.smoothstep(0, Curve.reducedMotionFade, t) : 1
        var isVisible = pillWidth > 0.25

        if let dismissedAt, time >= dismissedAt {
            let elapsed = time - dismissedAt
            if reduceMotion {
                let fade = 1 - Curve.smoothstep(0, Curve.reducedMotionFade, elapsed)
                visibility *= fade
                contentOpacity *= fade
                secondaryOpacity *= fade
                isVisible = elapsed < Curve.reducedMotionFade
            } else {
                let shrink = exp(-9 * Curve.smoothMax(elapsed - 0.09))
                let recenter = Curve.criticallyDamped(elapsed, omega: 10)
                let merge = Curve.criticallyDamped(elapsed, omega: 11)
                let round = Curve.criticallyDamped(elapsed, omega: 16)

                pillX += (rest.x - pillX) * recenter
                secondaryX += (pillX - secondaryX) * merge
                pillWidth = (targetWidth + (targetHeight - targetWidth) * round) * shrink
                pillHeight = targetHeight * shrink
                secondary = CGSize(width: secondary.width * shrink, height: secondary.height * shrink)
                y -= Curve.liftDistance * pow(Curve.clamp((elapsed - 0.02) / 0.48), 1.15)

                contentOpacity *= 1 - Curve.smoothstep(0.03, 0.20, elapsed)
                contentBlur = max(contentBlur, 8 * Curve.smoothstep(0.0, 0.18, elapsed))
                secondaryOpacity *= 1 - Curve.smoothstep(0.0, 0.10, elapsed)
                secondaryBlur = max(secondaryBlur, 6 * Curve.smoothstep(0.0, 0.10, elapsed))
                isVisible = pillWidth > 0.25 && elapsed < Curve.dismissDuration
            }
        }

        return LiquidCapsuleFrame(
            pill: .init(center: CGPoint(x: pillX, y: y), size: CGSize(width: pillWidth, height: pillHeight)),
            secondary: .init(center: CGPoint(x: secondaryX, y: y), size: secondary),
            contentOpacity: contentOpacity,
            contentBlur: contentBlur,
            secondaryOpacity: secondaryOpacity,
            secondaryBlur: secondaryBlur,
            ripple: reduceMotion ? nil : ripple(at: time, presentedAt: presentedAt, pillX: pillX),
            glow: glowValue(at: time),
            visibility: visibility,
            isSplit: splitValue > 0.9 && dismissedAt == nil,
            isVisible: isVisible
        )
    }

    private func ripple(at time: Double, presentedAt: Double, pillX: CGFloat) -> LiquidCapsuleFrame.Ripple? {
        let halfSize = CGSize(width: width.to / 2, height: height.to / 2)
        if let pulseAt, time >= pulseAt {
            return .init(center: CGPoint(x: pillX, y: Curve.restCenter.y), halfSize: halfSize, age: time - pulseAt, strength: 0.55)
        }
        let delay = Curve.appearRippleDelay
        let y = Curve.restCenter.y + Curve.riseDistance * exp(-1.65 * Curve.smoothMax(delay - 0.08))
        return .init(
            center: CGPoint(x: Curve.restCenter.x, y: y),
            halfSize: halfSize,
            age: time - presentedAt - delay,
            strength: 1
        )
    }
}
