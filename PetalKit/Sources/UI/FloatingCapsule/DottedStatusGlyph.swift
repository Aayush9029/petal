import SwiftUI

public struct DottedStatusGlyph: View {
    public enum Kind {
        case checkmark
        case clipboard
        case accessibility
        case warning
        case scissors
        case rabbit
        case speaker
    }

    private let kind: Kind
    private let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(kind: Kind, tint: Color) {
        self.kind = kind
        self.tint = tint
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let points = points(for: kind)
                let highlightedIndex = reduceMotion
                    ? -1
                    : Int(timeline.date.timeIntervalSinceReferenceDate * 8) % points.count

                for (index, point) in points.enumerated() {
                    let center = CGPoint(x: point.x * size.width, y: point.y * size.height)
                    let rect = CGRect(x: center.x - 1.25, y: center.y - 1.25, width: 2.5, height: 2.5)
                    let opacity = index == highlightedIndex ? 1 : 0.58
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: 1.25),
                        with: .color(tint.opacity(opacity))
                    )
                }
            }
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }

    private func points(for kind: Kind) -> [CGPoint] {
        switch kind {
        case .checkmark:
            [
                CGPoint(x: 0.12, y: 0.54),
                CGPoint(x: 0.27, y: 0.69),
                CGPoint(x: 0.42, y: 0.84),
                CGPoint(x: 0.55, y: 0.66),
                CGPoint(x: 0.68, y: 0.48),
                CGPoint(x: 0.81, y: 0.30),
                CGPoint(x: 0.94, y: 0.12),
            ]
        case .clipboard:
            [
                CGPoint(x: 0.34, y: 0.12),
                CGPoint(x: 0.50, y: 0.08),
                CGPoint(x: 0.66, y: 0.12),
                CGPoint(x: 0.20, y: 0.28),
                CGPoint(x: 0.80, y: 0.28),
                CGPoint(x: 0.20, y: 0.48),
                CGPoint(x: 0.80, y: 0.48),
                CGPoint(x: 0.20, y: 0.68),
                CGPoint(x: 0.80, y: 0.68),
                CGPoint(x: 0.30, y: 0.88),
                CGPoint(x: 0.50, y: 0.88),
                CGPoint(x: 0.70, y: 0.88),
            ]
        case .accessibility:
            [
                CGPoint(x: 0.50, y: 0.10),
                CGPoint(x: 0.22, y: 0.27),
                CGPoint(x: 0.78, y: 0.27),
                CGPoint(x: 0.12, y: 0.56),
                CGPoint(x: 0.50, y: 0.48),
                CGPoint(x: 0.88, y: 0.56),
                CGPoint(x: 0.30, y: 0.82),
                CGPoint(x: 0.70, y: 0.82),
            ]
        case .warning:
            [
                CGPoint(x: 0.50, y: 0.12),
                CGPoint(x: 0.50, y: 0.32),
                CGPoint(x: 0.50, y: 0.52),
                CGPoint(x: 0.50, y: 0.84),
            ]
        case .scissors:
            [
                CGPoint(x: 0.18, y: 0.22), CGPoint(x: 0.26, y: 0.30),
                CGPoint(x: 0.18, y: 0.78), CGPoint(x: 0.26, y: 0.70),
                CGPoint(x: 0.38, y: 0.40), CGPoint(x: 0.50, y: 0.50),
                CGPoint(x: 0.38, y: 0.60), CGPoint(x: 0.62, y: 0.42),
                CGPoint(x: 0.76, y: 0.32), CGPoint(x: 0.62, y: 0.58),
                CGPoint(x: 0.76, y: 0.68),
            ]
        case .rabbit:
            [
                CGPoint(x: 0.30, y: 0.12), CGPoint(x: 0.36, y: 0.30),
                CGPoint(x: 0.52, y: 0.10), CGPoint(x: 0.50, y: 0.32),
                CGPoint(x: 0.25, y: 0.42), CGPoint(x: 0.42, y: 0.38),
                CGPoint(x: 0.58, y: 0.46), CGPoint(x: 0.72, y: 0.56),
                CGPoint(x: 0.82, y: 0.48), CGPoint(x: 0.70, y: 0.72),
                CGPoint(x: 0.50, y: 0.76), CGPoint(x: 0.32, y: 0.70),
                CGPoint(x: 0.18, y: 0.58),
            ]
        case .speaker:
            [
                CGPoint(x: 0.12, y: 0.42), CGPoint(x: 0.12, y: 0.58),
                CGPoint(x: 0.28, y: 0.40), CGPoint(x: 0.28, y: 0.60),
                CGPoint(x: 0.44, y: 0.28), CGPoint(x: 0.44, y: 0.72),
                CGPoint(x: 0.62, y: 0.38), CGPoint(x: 0.68, y: 0.50),
                CGPoint(x: 0.62, y: 0.62), CGPoint(x: 0.78, y: 0.28),
                CGPoint(x: 0.88, y: 0.50), CGPoint(x: 0.78, y: 0.72),
            ]
        }
    }
}
