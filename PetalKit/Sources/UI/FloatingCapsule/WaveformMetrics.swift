import CoreGraphics

struct WaveformMetrics {
    let cell: CGFloat
    let gapX: CGFloat
    let pitchY: CGFloat
    let corner: CGFloat
    let inactiveCellOpacity: Double

    var pitchX: CGFloat { cell + gapX }

    func width(bars: Int) -> CGFloat {
        CGFloat(bars) * cell + CGFloat(max(bars - 1, 0)) * gapX
    }

    func height(rows: Int) -> CGFloat {
        cell + CGFloat(max(rows - 1, 0)) * pitchY
    }

    static let standard = WaveformMetrics(
        cell: 2,
        gapX: 2,
        pitchY: 3,
        corner: 1,
        inactiveCellOpacity: 0
    )

    static let floatingRecording = WaveformMetrics(
        cell: 2,
        gapX: 2,
        pitchY: 3,
        corner: 1,
        inactiveCellOpacity: 0
    )

    static let floating = WaveformMetrics(
        cell: 2,
        gapX: 2,
        pitchY: 3,
        corner: 1,
        inactiveCellOpacity: 0.2
    )
}
