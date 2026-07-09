import SwiftUI

enum DottedHelixRenderer {
    static func draw(
        phase: Double,
        bars: Int,
        rows: Int,
        tint: Color,
        metrics: WaveformMetrics,
        in context: GraphicsContext,
        size: CGSize
    ) {
        guard bars > 0, rows > 1 else { return }

        let contentWidth = metrics.width(bars: bars)
        let startX = (size.width - contentWidth) / 2
        let centerY = size.height / 2
        let rotations = bars >= 60 ? 3.0 : 2.0

        for index in 0..<bars {
            let position = Double(index) / Double(max(bars - 1, 1))
            let angle = phase + position * .pi * 2 * rotations
            let strandOffset = sin(angle)
            let frontRow = Int(round((strandOffset + 1) * 0.5 * Double(rows - 1)))
            let backRow = rows - frontRow - 1
            let x = startX + CGFloat(index) * metrics.pitchX

            if index.isMultiple(of: 3) {
                drawRung(
                    x: x,
                    from: frontRow,
                    to: backRow,
                    rows: rows,
                    tint: tint,
                    metrics: metrics,
                    centerY: centerY,
                    in: context
                )
            }

            let frontIsNear = cos(angle) >= 0
            drawCell(
                x: x,
                row: frontRow,
                rows: rows,
                opacity: frontIsNear ? 1 : 0.32,
                tint: tint,
                metrics: metrics,
                centerY: centerY,
                in: context
            )

            guard frontRow != backRow else { continue }
            drawCell(
                x: x,
                row: backRow,
                rows: rows,
                opacity: frontIsNear ? 0.32 : 1,
                tint: tint,
                metrics: metrics,
                centerY: centerY,
                in: context
            )
        }
    }

    private static func drawRung(
        x: CGFloat,
        from firstRow: Int,
        to secondRow: Int,
        rows: Int,
        tint: Color,
        metrics: WaveformMetrics,
        centerY: CGFloat,
        in context: GraphicsContext
    ) {
        let lowerRow = min(firstRow, secondRow)
        let upperRow = max(firstRow, secondRow)
        guard upperRow - lowerRow > 1 else { return }

        for row in (lowerRow + 1)..<upperRow {
            drawCell(
                x: x,
                row: row,
                rows: rows,
                opacity: 0.38,
                tint: tint,
                metrics: metrics,
                centerY: centerY,
                in: context
            )
        }
    }

    private static func drawCell(
        x: CGFloat,
        row: Int,
        rows: Int,
        opacity: Double,
        tint: Color,
        metrics: WaveformMetrics,
        centerY: CGFloat,
        in context: GraphicsContext
    ) {
        let rowY = centerY + (CGFloat(row) - CGFloat(rows - 1) / 2) * metrics.pitchY
        let rect = CGRect(
            x: x,
            y: rowY - metrics.cell / 2,
            width: metrics.cell,
            height: metrics.cell
        )
        context.fill(
            Path(roundedRect: rect, cornerRadius: metrics.corner),
            with: .color(tint.opacity(opacity))
        )
    }
}
