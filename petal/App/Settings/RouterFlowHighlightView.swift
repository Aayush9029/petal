import AppKit
import QuartzCore

/// The highlight that travels along the active branch. The render server runs it, so the Settings window
/// does not update SwiftUI on every frame.
final class RouterFlowHighlightView: NSView {
    struct Style: Equatable {
        var slot: Int
        var isAnimating: Bool
        var glowColor: CGColor
    }

    var style: Style? {
        didSet {
            guard style != oldValue else { return }
            needsLayout = true
        }
    }

    private static let period: CFTimeInterval = 2
    /// The head runs past the end of the branch, so the trail drains out before the next pass starts.
    private static let travel = 1.3
    private static let segmentLength = 0.035
    private static let segmentOpacities: [Float] = [0.85, 0.65, 0.45, 0.25]

    private let glowLayer = CALayer()
    private let segmentLayers: [CAShapeLayer]

    override init(frame frameRect: NSRect) {
        segmentLayers = Self.segmentOpacities.map { opacity in
            let layer = CAShapeLayer()
            layer.fillColor = nil
            layer.strokeColor = CGColor(gray: 1, alpha: CGFloat(opacity))
            layer.lineWidth = 2
            layer.lineCap = .round
            return layer
        }
        super.init(frame: frameRect)
        wantsLayer = true
        glowLayer.shadowOpacity = 0.8
        glowLayer.shadowRadius = 3
        glowLayer.shadowOffset = .zero
        segmentLayers.forEach(glowLayer.addSublayer)
        layer?.addSublayer(glowLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        render()
    }

    private func render() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        segmentLayers.forEach { $0.removeAllAnimations() }
        guard let style, style.isAnimating, bounds.width > 0 else {
            glowLayer.isHidden = true
            return
        }

        let path = RouterFlowLayout.activePath(slot: style.slot, width: bounds.width)
        let scale = window?.backingScaleFactor ?? 2
        glowLayer.isHidden = false
        glowLayer.frame = bounds
        glowLayer.shadowColor = style.glowColor
        for (step, segment) in segmentLayers.enumerated() {
            segment.frame = bounds
            segment.contentsScale = scale
            segment.path = path
            segment.strokeStart = 0
            segment.strokeEnd = 0
            segment.add(animation(step: step), forKey: "flow")
        }
    }

    /// Each segment trails the one before it by its own length, and is trimmed where it enters and leaves the branch.
    private func animation(step: Int) -> CAAnimation {
        let lag = Double(step) * Self.segmentLength
        let enters = lag / Self.travel
        let reachesEnd = (1 + lag) / Self.travel
        let tailEnters = (lag + Self.segmentLength) / Self.travel
        let leaves = (1 + lag + Self.segmentLength) / Self.travel

        let end = CAKeyframeAnimation(keyPath: "strokeEnd")
        end.values = [0, 0, 1, 1]
        end.keyTimes = [0, enters, reachesEnd, 1].map { NSNumber(value: $0) }

        let start = CAKeyframeAnimation(keyPath: "strokeStart")
        start.values = [0, 0, 1, 1]
        start.keyTimes = [0, tailEnters, leaves, 1].map { NSNumber(value: $0) }

        let visibility = CAKeyframeAnimation(keyPath: "opacity")
        visibility.calculationMode = .discrete
        visibility.values = [0, 1, 0]
        visibility.keyTimes = [0, enters, leaves, 1].map { NSNumber(value: $0) }

        let group = CAAnimationGroup()
        group.animations = [end, start, visibility]
        group.duration = Self.period
        group.repeatCount = .infinity
        group.isRemovedOnCompletion = false
        // Keeps the phase on the wall clock, so a relayout does not restart the pass.
        let phase = Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.period)
        group.beginTime = segmentLayers[step].convertTime(CACurrentMediaTime(), from: nil) - phase
        return group
    }
}
