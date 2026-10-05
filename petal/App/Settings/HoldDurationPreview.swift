import SwiftUI

/// Fills a track over the threshold's own duration. Every card shares one wall-clock cycle and one absolute
/// track length, so a short hold visibly stops short of a long one instead of each filling its own width.
struct HoldDurationPreview: View {
    let seconds: Double
    let longestSeconds: Double
    let tint: Color

    private static let holdDuration: Double = 0.55
    private static let gapDuration: Double = 0.45

    var body: some View {
        HoldDurationTrack(
            span: span,
            fillDuration: seconds,
            holdDuration: Self.holdDuration,
            cycle: longestSeconds + Self.holdDuration + Self.gapDuration,
            tint: tint
        )
        .frame(height: 6)
        .allowsHitTesting(false)
    }

    private var span: Double {
        longestSeconds > 0 ? min(1, seconds / longestSeconds) : 1
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        HoldDurationPreview(seconds: 0.4, longestSeconds: 2, tint: .primary)
        HoldDurationPreview(seconds: 1.0, longestSeconds: 2, tint: .primary)
        HoldDurationPreview(seconds: 2.0, longestSeconds: 2, tint: .primary)
    }
    .frame(width: 180)
    .padding()
}
