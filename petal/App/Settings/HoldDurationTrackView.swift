import AppKit
import QuartzCore

/// The render server runs the fill animation, so the Settings window does not update SwiftUI on every frame.
final class HoldDurationTrackView: NSView {
    struct Style: Equatable {
        /// The part of the track the fill reaches, from 0 to 1.
        var span: Double
        var fillDuration: Double
        var holdDuration: Double
        var cycle: Double
        var trackColor: CGColor
        var fillColor: CGColor
        var isAnimated: Bool
    }

    var style: Style? {
        didSet {
            guard style != oldValue else { return }
            needsLayout = true
        }
    }

    private let trackLayer = CALayer()
    private let fillLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        fillLayer.anchorPoint = CGPoint(x: 0, y: 0.5)
        layer?.addSublayer(trackLayer)
        layer?.addSublayer(fillLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    /// The track sits inside a card's button, so clicks pass through to it.
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        render()
    }

    private func render() {
        guard let style, bounds.width > 0, bounds.height > 0 else { return }
        let height = bounds.height
        let fullWidth = bounds.width * style.span

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        trackLayer.frame = bounds
        trackLayer.cornerRadius = height / 2
        trackLayer.backgroundColor = style.trackColor

        fillLayer.cornerRadius = height / 2
        fillLayer.backgroundColor = style.fillColor
        fillLayer.position = CGPoint(x: 0, y: height / 2)
        fillLayer.bounds = CGRect(x: 0, y: 0, width: max(height, fullWidth), height: height)
        fillLayer.removeAllAnimations()

        guard style.isAnimated, style.cycle > 0, style.fillDuration > 0 else { return }
        fillLayer.add(fillAnimation(style: style, height: height, fullWidth: fullWidth), forKey: "fill")
    }

    /// Grows from a dot to the full span, holds, then hides until the cycle ends.
    private func fillAnimation(style: Style, height: CGFloat, fullWidth: CGFloat) -> CAAnimation {
        let cycle = style.cycle
        let dotEnds = fullWidth > height ? style.fillDuration * height / fullWidth : style.fillDuration

        let width = CAKeyframeAnimation(keyPath: "bounds.size.width")
        width.values = [height, height, max(height, fullWidth), max(height, fullWidth)]
        width.keyTimes = [0, dotEnds / cycle, style.fillDuration / cycle, 1].map { NSNumber(value: $0) }
        width.duration = cycle

        let visibility = CAKeyframeAnimation(keyPath: "opacity")
        visibility.calculationMode = .discrete
        visibility.values = [1, 0]
        visibility.keyTimes = [0, (style.fillDuration + style.holdDuration) / cycle, 1].map { NSNumber(value: $0) }
        visibility.duration = cycle

        let group = CAAnimationGroup()
        group.animations = [width, visibility]
        group.duration = cycle
        group.repeatCount = .infinity
        group.isRemovedOnCompletion = false
        // Every card shares one wall-clock cycle, so a restart lands on the same phase.
        let phase = Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
        group.beginTime = fillLayer.convertTime(CACurrentMediaTime(), from: nil) - phase
        return group
    }
}
