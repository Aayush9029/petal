import SwiftUI

/// A capsule whose round ends follow a superellipse, matching `squircle()` in LiquidGlass.metal.
public struct Squircle: Shape {
    public var exponent: Double = 2.15

    public init(exponent: Double = 2.15) {
        self.exponent = exponent
    }

    public func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        guard radius > 0 else { return Path() }
        let inner = rect.insetBy(dx: radius, dy: radius)
        let corners: [(center: CGPoint, start: Double)] = [
            (CGPoint(x: inner.maxX, y: inner.maxY), 0),
            (CGPoint(x: inner.minX, y: inner.maxY), .pi / 2),
            (CGPoint(x: inner.minX, y: inner.minY), .pi),
            (CGPoint(x: inner.maxX, y: inner.minY), 3 * .pi / 2),
        ]
        let steps = 24
        var path = Path()
        for (index, corner) in corners.enumerated() {
            for step in 0...steps {
                let angle = corner.start + Double(step) / Double(steps) * .pi / 2
                let c = cos(angle), s = sin(angle)
                let point = CGPoint(
                    x: corner.center.x + radius * copysign(pow(abs(c), 2 / exponent), c),
                    y: corner.center.y + radius * copysign(pow(abs(s), 2 / exponent), s)
                )
                if index == 0 && step == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
        path.closeSubpath()
        return path
    }
}
