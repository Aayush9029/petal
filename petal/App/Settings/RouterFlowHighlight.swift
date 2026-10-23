import SwiftUI

struct RouterFlowHighlight: NSViewRepresentable {
    let slot: Int
    let glow: Color
    let isAnimating: Bool

    func makeNSView(context: Context) -> RouterFlowHighlightView {
        RouterFlowHighlightView()
    }

    func updateNSView(_ view: RouterFlowHighlightView, context: Context) {
        view.style = RouterFlowHighlightView.Style(
            slot: slot,
            isAnimating: isAnimating,
            glowColor: glow.resolve(in: context.environment).cgColor
        )
    }
}
