import SwiftUI

enum WaveformCanvasRenderer {
    static func draw(
        values: [Double],
        rows: Int,
        tint: Color,
        metrics: WaveformMetrics,
        in context: GraphicsContext,
        size: CGSize
    ) {
        guard !values.isEmpty, rows > 0 else { return }

        let contentWidth = metrics.width(bars: values.count)
        let startX = (size.width - contentWidth) / 2
        let centerY = size.height / 2

        for (index, rawValue) in values.enumerated() {
            let value = min(max(rawValue, 0), 1)
            let x = startX + CGFloat(index) * metrics.pitchX
            let litRows = litRowCount(for: value, rows: rows)
            let firstLitRow = (rows - litRows) / 2

            for row in firstLitRow..<(firstLitRow + litRows) {
                let rowY = centerY + (CGFloat(row) - CGFloat(rows - 1) / 2) * metrics.pitchY
                drawCell(x: x, centerY: rowY, opacity: 1, tint: tint, metrics: metrics, in: context)
            }
        }
    }

    static func drawHelix(
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

        for index in 0..<bars {
            let position = Double(index) / Double(max(bars - 1, 1))
            let angle = phase + position * .pi * 4
            let normalizedOffset = sin(angle)
            let firstRow = Int(round((normalizedOffset + 1) * 0.5 * Double(rows - 1)))
            let secondRow = rows - firstRow - 1
            let x = startX + CGFloat(index) * metrics.pitchX

            if index.isMultiple(of: 4) {
                let lowerRow = min(firstRow, secondRow)
                let upperRow = max(firstRow, secondRow)
                if upperRow - lowerRow > 1 {
                    for row in (lowerRow + 1)..<upperRow {
                        let rowY = centerY + (CGFloat(row) - CGFloat(rows - 1) / 2) * metrics.pitchY
                        drawCell(x: x, centerY: rowY, opacity: 0.28, tint: tint, metrics: metrics, in: context)
                    }
                }
            }

            let firstY = centerY + (CGFloat(firstRow) - CGFloat(rows - 1) / 2) * metrics.pitchY
            let secondY = centerY + (CGFloat(secondRow) - CGFloat(rows - 1) / 2) * metrics.pitchY
            let firstIsForward = cos(angle) >= 0

            drawCell(
                x: x,
                centerY: firstY,
                opacity: firstIsForward ? 1 : 0.42,
                tint: tint,
                metrics: metrics,
                in: context
            )
            if firstRow != secondRow {
                drawCell(
                    x: x,
                    centerY: secondY,
                    opacity: firstIsForward ? 0.42 : 1,
                    tint: tint,
                    metrics: metrics,
                    in: context
                )
            }
        }
    }

    private static func litRowCount(for value: Double, rows: Int) -> Int {
        if rows.isMultiple(of: 2) {
            let pairs = max(1, Int(ceil(value * Double(rows / 2))))
            return min(rows, pairs * 2)
        }

        let maxHalf = rows / 2
        return 1 + PixelEQ.litHalf(value, maxHalf: maxHalf) * 2
    }

    private static func drawCell(
        x: CGFloat,
        centerY: CGFloat,
        opacity: Double,
        tint: Color,
        metrics: WaveformMetrics,
        in context: GraphicsContext
    ) {
        let rect = CGRect(
            x: x,
            y: centerY - metrics.cell / 2,
            width: metrics.cell,
            height: metrics.cell
        )
        context.fill(
            Path(roundedRect: rect, cornerRadius: metrics.corner),
            with: .color(tint.opacity(opacity))
        )
    }
}
