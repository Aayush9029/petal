import SwiftUI

/// Draws the spine from the voice node through the router, and a branch to each route card.
/// A soft highlight travels along the active branch.
struct RouterFlowConnectors: View {
    /// Route cards plus the add card, which is always last.
    let slotCount: Int
    let activeSlot: Int?
    let isFlowing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isAnimating)) { timeline in
            Canvas { context, size in
                draw(in: &context, width: size.width, time: isAnimating ? timeline.date.timeIntervalSinceReferenceDate : nil)
            }
        }
        .frame(height: RouterFlowLayout.height(slots: slotCount))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Stops redrawing while Settings is in the background, so an idle window costs no CPU.
    private var isAnimating: Bool {
        isFlowing && activeSlot != nil && !reduceMotion && controlActiveState != .inactive
    }

    private func draw(in context: inout GraphicsContext, width: CGFloat, time: TimeInterval?) {
        let spineX = width / 2
        let idle = GraphicsContext.Shading.color(.primary.opacity(0.14))
        let thin = StrokeStyle(lineWidth: 1.25, lineCap: .round)
        let lastY = RouterFlowLayout.midY(slot: slotCount - 1)

        var spine = Path()
        spine.move(to: CGPoint(x: spineX, y: RouterFlowLayout.hubSize))
        spine.addLine(to: CGPoint(x: spineX, y: RouterFlowLayout.routerTop))
        spine.move(to: CGPoint(x: spineX, y: RouterFlowLayout.routerBottom))
        spine.addLine(to: CGPoint(x: spineX, y: lastY))
        context.stroke(spine, with: idle, style: thin)

        for slot in 0 ..< slotCount where slot != activeSlot || !isFlowing {
            let isGhost = slot == slotCount - 1
            context.stroke(
                stub(slot: slot, spineX: spineX, width: width),
                with: idle,
                style: isGhost ? StrokeStyle(lineWidth: 1, lineCap: .round, dash: [2, 4]) : thin
            )
        }

        guard let activeSlot, isFlowing else { return }

        let active = activePath(slot: activeSlot, spineX: spineX, width: width)
        let accent = Color.accentColor
        context.stroke(active, with: .color(accent.opacity(0.85)), style: StrokeStyle(lineWidth: 1.75, lineCap: .round))
        context.fill(port(at: edge(slot: activeSlot, spineX: spineX, width: width)), with: .color(accent))

        guard let time else { return }
        let period = 2.0
        let head = (time.truncatingRemainder(dividingBy: period) / period) * 1.3
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: accent.opacity(0.8), radius: 3))
            for step in 0 ..< 4 {
                let to = head - Double(step) * 0.035
                let from = to - 0.035
                guard to > 0, from < 1 else { continue }
                layer.stroke(
                    active.trimmedPath(from: max(from, 0), to: min(to, 1)),
                    with: .color(.white.opacity(0.85 - Double(step) * 0.2)),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
            }
        }
    }

    private func edge(slot: Int, spineX: CGFloat, width: CGFloat) -> CGPoint {
        let column = RouterFlowLayout.columnWidth(in: width)
        let x = RouterFlowLayout.isLeft(slot: slot) ? column : column + RouterFlowLayout.spineGap
        return CGPoint(x: x, y: RouterFlowLayout.midY(slot: slot))
    }

    private func stub(slot: Int, spineX: CGFloat, width: CGFloat) -> Path {
        let end = edge(slot: slot, spineX: spineX, width: width)
        return Path { path in
            path.move(to: CGPoint(x: spineX, y: end.y))
            path.addLine(to: end)
        }
    }

    /// Voice to router, down the spine, then a rounded turn into the card.
    private func activePath(slot: Int, spineX: CGFloat, width: CGFloat) -> Path {
        let end = edge(slot: slot, spineX: spineX, width: width)
        let radius = min(RouterFlowLayout.cornerRadius, abs(end.x - spineX))
        let direction: CGFloat = end.x < spineX ? -1 : 1
        return Path { path in
            path.move(to: CGPoint(x: spineX, y: RouterFlowLayout.hubSize))
            path.addLine(to: CGPoint(x: spineX, y: RouterFlowLayout.routerTop))
            path.move(to: CGPoint(x: spineX, y: RouterFlowLayout.routerBottom))
            path.addLine(to: CGPoint(x: spineX, y: end.y - radius))
            path.addQuadCurve(to: CGPoint(x: spineX + direction * radius, y: end.y), control: CGPoint(x: spineX, y: end.y))
            path.addLine(to: end)
        }
    }

    private func port(at point: CGPoint, radius: CGFloat = 2.5) -> Path {
        Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
    }
}

#Preview {
    VStack(spacing: 30) {
        RouterFlowConnectors(slotCount: 4, activeSlot: 1, isFlowing: true)
        RouterFlowConnectors(slotCount: 3, activeSlot: 0, isFlowing: false)
    }
    .frame(width: 420)
    .padding()
}
