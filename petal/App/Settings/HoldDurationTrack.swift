import SwiftUI

struct HoldDurationTrack: NSViewRepresentable {
    let span: Double
    let fillDuration: Double
    let holdDuration: Double
    let cycle: Double
    let tint: Color

    func makeNSView(context: Context) -> HoldDurationTrackView {
        HoldDurationTrackView()
    }

    func updateNSView(_ view: HoldDurationTrackView, context: Context) {
        view.style = HoldDurationTrackView.Style(
            span: span,
            fillDuration: fillDuration,
            holdDuration: holdDuration,
            cycle: cycle,
            trackColor: tint.opacity(0.18).resolve(in: context.environment).cgColor,
            fillColor: tint.resolve(in: context.environment).cgColor,
            isAnimated: !context.environment.accessibilityReduceMotion
        )
    }
}
