import SwiftUI

struct RouterFlowHighlight: NSViewRepresentable {
    let slot: Int
    let isAnimating: Bool

    func makeNSView(context: Context) -> RouterFlowHighlightView {
        RouterFlowHighlightView()
    }

    func updateNSView(_ view: RouterFlowHighlightView, context: Context) {
        view.style = RouterFlowHighlightView.Style(
            slot: slot,
            isAnimating: isAnimating,
            glowColor: Color.accentColor.resolve(in: context.environment).cgColor
        )
    }
}
