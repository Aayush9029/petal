import CoreGraphics
import Foundation

/// The events of one capsule session. Frames are a pure function of these
/// events and the time, so any instant can be rendered or tested on its own.
struct CapsuleTimeline: Equatable, Sendable {
    private typealias Curve = CapsuleChoreography

    enum DismissStyle: Equatable, Sendable {
        /// Merge, shrink, and lift away: the session finished.
        case shrink
        /// The glass pops into droplets: the recording was discarded.
        case burst
    }

    static let defaultSize = CGSize(width: 198, height: CapsuleChoreography.pillHeight)

    private(set) var presentedAt: Double?
    private(set) var dismissedAt: Double?
    private(set) var pulseAt: Double?
    private(set) var dismissStyle = DismissStyle.shrink
    private(set) var orbitStart: Double?
    private(set) var orbitEnd: Double?
    private var width = CapsuleSpring(defaultSize.width, omega: 11)
    private var height = CapsuleSpring(defaultSize.height, omega: 11)
    private var split = CapsuleSpring(0, omega: 12)
    private var stopHover = CapsuleSpring(0, omega: 14)
    private var transcribeHover = CapsuleSpring(0, omega: 14)
    private var danger = CapsuleSpring(0, omega: 9)
    private var glowFrom = SIMD3<Double>.zero
    private var glowTo = SIMD3<Double>.zero
    private var glowStart = -Double.infinity
    var reduceMotion = false

    var isPresented: Bool { presentedAt != nil && dismissedAt == nil }

    var lastEventTime: Double {
        [
            presentedAt, dismissedAt, pulseAt, width.start, height.start, split.start,
            stopHover.start, transcribeHover.start, danger.start, glowStart,
        ]
            .compactMap { $0 }
            .filter(\.isFinite)
            .max() ?? 0
    }

    /// The time after which the frame no longer changes.
    var settledTime: Double {
        if let dismissedAt {
            let duration = dismissStyle == .burst && !reduceMotion
                ? Curve.burstDuration
                : Curve.dismissDuration(reduceMotion: reduceMotion)
            return dismissedAt + duration
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
        stopHover.retarget(0, at: time, snap: true)
        transcribeHover.retarget(0, at: time, snap: true)
        danger.retarget(0, at: time, snap: true)
        dismissStyle = .shrink
        orbitStart = nil
        orbitEnd = nil
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

    /// The pointer is over the stop drop or over the Transcribe pill.
    mutating func setHover(stop: Bool, transcribe: Bool, at time: Double) {
        guard isPresented else { return }
        stopHover.retarget(stop ? 1 : 0, at: time)
        transcribeHover.retarget(transcribe ? 1 : 0, at: time)
    }

    /// The recording is about to be deleted: the highlights turn red.
    mutating func setDanger(_ isDanger: Bool, at time: Double) {
        guard isPresented else { return }
        danger.retarget(isDanger ? 1 : 0, at: time)
    }

    /// The highlight orbits the rim while the capsule processes.
    mutating func setOrbit(_ isOrbiting: Bool, at time: Double) {
        guard isPresented else { return }
        if isOrbiting {
            guard orbitStart == nil || orbitEnd != nil else { return }
            orbitStart = time
            orbitEnd = nil
        } else if orbitStart != nil, orbitEnd == nil {
            orbitEnd = time
        }
    }

    /// Head position of the orbiting highlight in turns around the rim, and its strength.
    /// The highlight speeds up from rest when processing starts and coasts to rest when it ends.
    func orbit(at time: Double) -> (turns: Double, strength: Double) {
        guard let orbitStart, time > orbitStart else { return (0, 0) }
        let ramp = Curve.orbitRamp
        let speed = Curve.orbitTurnsPerSecond
        // Distance covered by a speed that eases from 0 to 1 over `ramp` seconds.
        func easedDistance(_ elapsed: Double) -> Double {
            let u = Curve.clamp(elapsed / ramp)
            return ramp * (u * u * u - u * u * u * u / 2) + max(elapsed - ramp, 0)
        }
        func easedSpeed(_ elapsed: Double) -> Double { Curve.smoothstep(0, ramp, elapsed) }

        let end = orbitEnd ?? .infinity
        let running = min(time, end) - orbitStart
        var turns = speed * easedDistance(running)
        var strength = Curve.smoothstep(0, 0.5, running)
        if time > end {
            let coast = min(time - end, ramp)
            let u = coast / ramp
            // The speed falls from its value at the end to rest along an eased curve.
            turns += speed * easedSpeed(running) * ramp * (u - (u * u * u - u * u * u * u / 2))
            strength *= 1 - Curve.smoothstep(0, ramp, time - end)
        }
        return (turns.truncatingRemainder(dividingBy: 1), strength)
    }

    var isOrbiting: Bool { orbitStart != nil && orbitEnd == nil }

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

    mutating func dismiss(at time: Double, style: DismissStyle = .shrink) {
        guard isPresented else { return }
        dismissedAt = time
        dismissStyle = style
    }

    private func glowValue(at time: Double) -> SIMD3<Double> {
        glowFrom + (glowTo - glowFrom) * Curve.smoothstep(0, 0.35, time - glowStart)
    }

    func frame(at time: Double) -> CapsuleFrame {
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

        // Tucked, the drop is a small bead at the centre of the pill's end cap,
        // fully inside the glass, so it can appear and vanish without a visible change.
        let tucked = Curve.tuckedScale * targetHeight
        let tuckedX = rest.x + targetWidth / 2 - targetHeight / 2
        let splitX = rest.x - pairShift + targetWidth / 2 + Curve.gap + secondarySize.width / 2
        var secondaryX = tuckedX + (splitX - tuckedX) * splitValue
        let swell = Curve.smoothstep(0, 0.6, splitValue)
        var secondary = split.to > 0 || splitValue > 0.002
            ? CGSize(
                width: (tucked + (secondarySize.width - tucked) * swell) * grow,
                height: (tucked + (secondarySize.height - tucked) * swell) * grow
            )
            : .zero

        if let pulseAt, !reduceMotion, time > pulseAt {
            let age = time - pulseAt
            let wobble = 0.07 * sin(age * 2 * .pi * 2.4) * exp(-age * 5.5)
            pillHeight *= 1 - wobble
            pillWidth *= 1 + 0.4 * wobble
        }

        var contentOpacity = reduceMotion
            ? Curve.smoothstep(0, Curve.reducedMotionFade, t)
            : Curve.smoothstep(0.24, 0.46, t)
        // The content waits until the drop is almost full width, so it does not stretch with it.
        var contentBlur = reduceMotion ? 0 : 7 * (1 - Curve.smoothstep(0.22, 0.46, t))
        var secondaryOpacity = Curve.smoothstep(0.55, 0.95, splitValue)
        var secondaryBlur = reduceMotion ? 0 : 6 * (1 - secondaryOpacity)
        var visibility = reduceMotion ? Curve.smoothstep(0, Curve.reducedMotionFade, t) : 1
        var diffusion = reduceMotion ? 0 : 1 - Curve.smoothstep(0.0, 0.45, t)
        if let pulseAt, !reduceMotion, time > pulseAt {
            diffusion = max(diffusion, 0.6 * exp(-(time - pulseAt) * 5))
        }
        var isVisible = pillWidth > 0.25
        var glassBlur = 0.0

        var burstAge: Double?
        var burstRipple: CapsuleFrame.Ripple?
        if let dismissedAt, time >= dismissedAt {
            let elapsed = time - dismissedAt
            if dismissStyle == .burst, !reduceMotion {
                let swell = 1 + 0.07 * Curve.smoothstep(0, 0.07, elapsed)
                pillWidth *= swell
                pillHeight *= swell
                secondary = CGSize(width: secondary.width * swell, height: secondary.height * swell)
                visibility *= 1 - Curve.smoothstep(0.05, 0.16, elapsed)
                contentOpacity *= 1 - Curve.smoothstep(0, 0.08, elapsed)
                contentBlur = max(contentBlur, 10 * Curve.smoothstep(0, 0.1, elapsed))
                secondaryOpacity *= 1 - Curve.smoothstep(0, 0.08, elapsed)
                secondaryBlur = max(secondaryBlur, 8 * Curve.smoothstep(0, 0.1, elapsed))
                diffusion = max(diffusion, Curve.smoothstep(0, 0.12, elapsed))
                isVisible = elapsed < Curve.burstDuration
                burstAge = elapsed
                burstRipple = .init(
                    center: CGPoint(x: pillX, y: y),
                    halfSize: CGSize(width: targetWidth / 2, height: targetHeight / 2),
                    age: elapsed,
                    strength: 1
                )
            } else if reduceMotion {
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
                diffusion = max(diffusion, Curve.smoothstep(0.0, 0.25, elapsed))
                glassBlur = 8 * Curve.smoothstep(0.06, 0.40, elapsed)
                visibility *= 1 - Curve.smoothstep(0.28, 0.52, elapsed)
            }
        }

        return CapsuleFrame(
            pill: .init(center: CGPoint(x: pillX, y: y), size: CGSize(width: pillWidth, height: pillHeight)),
            secondary: .init(center: CGPoint(x: secondaryX, y: y), size: secondary),
            contentOpacity: contentOpacity,
            contentBlur: contentBlur,
            secondaryOpacity: secondaryOpacity,
            secondaryBlur: secondaryBlur,
            ripple: reduceMotion ? nil : burstRipple ?? ripple(at: time, presentedAt: presentedAt, pillX: pillX),
            glow: glowValue(at: time),
            visibility: visibility,
            diffusion: diffusion,
            glassBlur: glassBlur,
            isDismissing: dismissedAt.map { time >= $0 } ?? false,
            stopHover: reduceMotion ? stopHover.to : stopHover.value(at: time),
            transcribeHover: reduceMotion ? transcribeHover.to : transcribeHover.value(at: time),
            danger: reduceMotion ? danger.to : Curve.clamp(danger.value(at: time)),
            burstAge: burstAge,
            isSplit: splitValue > 0.9 && dismissedAt == nil,
            isVisible: isVisible
        )
    }

    private func ripple(at time: Double, presentedAt: Double, pillX: CGFloat) -> CapsuleFrame.Ripple? {
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
