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
            let litRange = firstLitRow..<(firstLitRow + litRows)

            for row in 0..<rows {
                let opacity = litRange.contains(row) ? 1 : metrics.inactiveCellOpacity
                guard opacity > 0 else { continue }
                let rowY = centerY + (CGFloat(row) - CGFloat(rows - 1) / 2) * metrics.pitchY
                drawCell(x: x, centerY: rowY, opacity: opacity, tint: tint, metrics: metrics, in: context)
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
