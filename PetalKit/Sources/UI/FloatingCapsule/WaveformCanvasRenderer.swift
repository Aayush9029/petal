import SwiftUI

enum WaveformCanvasRenderer {
    static func draw(
        values: [Double],
        opacities: [Double]? = nil,
        maxHalf: Int,
        tint: Color,
        in context: GraphicsContext,
        size: CGSize
    ) {
        guard !values.isEmpty else { return }

        let contentWidth = PixelEQ.width(bars: values.count)
        let startX = (size.width - contentWidth) / 2
        let centerY = size.height / 2

        for (index, rawValue) in values.enumerated() {
            let value = min(max(rawValue, 0), 1)
            let columnOpacity: Double
            if let opacities, opacities.indices.contains(index) {
                columnOpacity = opacities[index]
            } else {
                columnOpacity = 1
            }
            let x = startX + CGFloat(index) * PixelEQ.pitchX

            drawCell(
                x: x,
                centerY: centerY,
                opacity: columnOpacity * (0.48 + value * 0.52),
                tint: tint,
                in: context
            )

            let activation = value * Double(maxHalf) * 1.12
            guard maxHalf > 0 else { continue }

            for half in 1...maxHalf {
                let rowOpacity = min(max(activation - Double(half - 1), 0), 1)
                guard rowOpacity > 0.01 else { continue }

                let distance = CGFloat(half) * PixelEQ.pitchY
                let opacity = columnOpacity * rowOpacity
                drawCell(x: x, centerY: centerY - distance, opacity: opacity, tint: tint, in: context)
                drawCell(x: x, centerY: centerY + distance, opacity: opacity, tint: tint, in: context)
            }
        }
    }

    private static func drawCell(
        x: CGFloat,
        centerY: CGFloat,
        opacity: Double,
        tint: Color,
        in context: GraphicsContext
    ) {
        let rect = CGRect(
            x: x,
            y: centerY - PixelEQ.cell / 2,
            width: PixelEQ.cell,
            height: PixelEQ.cell
        )
        context.fill(
            Path(roundedRect: rect, cornerRadius: PixelEQ.corner),
            with: .color(tint.opacity(opacity))
        )
    }
}
