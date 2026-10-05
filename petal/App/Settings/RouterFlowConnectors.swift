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
        Canvas { context, size in
            draw(in: &context, width: size.width)
        }
        .overlay {
            if isFlowing, let activeSlot {
                RouterFlowHighlight(slot: activeSlot, isAnimating: isAnimating)
            }
        }
        .frame(height: RouterFlowLayout.height(slots: slotCount))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Stops the highlight while Settings is in the background.
    private var isAnimating: Bool {
        !reduceMotion && controlActiveState != .inactive
    }

    private func draw(in context: inout GraphicsContext, width: CGFloat) {
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

        let accent = Color.accentColor
        context.stroke(
            Path(RouterFlowLayout.activePath(slot: activeSlot, width: width)),
            with: .color(accent.opacity(0.85)),
            style: StrokeStyle(lineWidth: 1.75, lineCap: .round)
        )
        context.fill(port(at: RouterFlowLayout.edge(slot: activeSlot, width: width)), with: .color(accent))
    }

    private func stub(slot: Int, spineX: CGFloat, width: CGFloat) -> Path {
        let end = RouterFlowLayout.edge(slot: slot, width: width)
        return Path { path in
            path.move(to: CGPoint(x: spineX, y: end.y))
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
