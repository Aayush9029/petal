import CoreGraphics

struct WaveformMetrics {
    let cell: CGFloat
    let gapX: CGFloat
    let pitchY: CGFloat
    let corner: CGFloat

    var pitchX: CGFloat { cell + gapX }

    func width(bars: Int) -> CGFloat {
        CGFloat(bars) * cell + CGFloat(max(bars - 1, 0)) * gapX
    }

    func height(rows: Int) -> CGFloat {
        cell + CGFloat(max(rows - 1, 0)) * pitchY
    }

    static let standard = WaveformMetrics(
        cell: PixelEQ.cell,
        gapX: PixelEQ.gapX,
        pitchY: PixelEQ.pitchY,
        corner: PixelEQ.corner
    )

    /// The floating capsule has more, smaller, fully opaque dots than the
    /// expanded waveform. Integer-friendly dimensions keep them crisp on a
    /// Retina display instead of reading as a soft continuous bar.
    static let floating = WaveformMetrics(
        cell: 2,
        gapX: 2,
        pitchY: 3,
        corner: 1
    )
}
