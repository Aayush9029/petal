import AppKit
import UI

enum MenuBarIconRenderer {
    private static let grid = 9
    private static let canvas: CGFloat = 18

    // The source artwork already includes its own margin.
    private static let contentInset: CGFloat = 0.02

    static let idlePetal: NSImage? = {
        guard let base = NSImage(named: "menuBarPetal") else { return nil }
        let size = NSSize(width: canvas, height: canvas)
        let inset = canvas * contentInset
        let image = NSImage(size: size, flipped: false) { _ in
            base.draw(in: NSRect(x: inset, y: inset, width: canvas - 2 * inset, height: canvas - 2 * inset))
            return true
        }
        image.isTemplate = true
        return image
    }()

    static let dropTarget = image(cells: [
        Cell(col: 4, row: 2),
        Cell(col: 4, row: 3),
        Cell(col: 2, row: 4),
        Cell(col: 3, row: 4),
        Cell(col: 4, row: 4),
        Cell(col: 5, row: 4),
        Cell(col: 6, row: 4),
        Cell(col: 4, row: 5),
        Cell(col: 4, row: 6),
    ])

    static func recording(level: Double) -> NSImage {
        let power = pow(max(0, min(1, level)), 1.25) * 0.94
        return barsImage(values: recordingProfile.map { $0 * power })
    }

    static func working(tick: Int) -> NSImage {
        let values = (0..<recordingProfile.count).map { index in
            0.5 + 0.5 * sin(Double(tick) * 0.3 + Double(index) * 1.1)
        }
        return barsImage(values: values)
    }

    static func error() -> NSImage {
        let cells = [
            Cell(col: 4, row: 1),
            Cell(col: 4, row: 2),
            Cell(col: 4, row: 3),
            Cell(col: 4, row: 4),
            Cell(col: 4, row: 6),
        ]
        return image(cells: cells)
    }

    private struct Cell {
        let col: Int
        let row: Int
    }

    private static let recordingProfile: [Double] = [0.46, 0.78, 1.0, 0.6]

    private static func barsImage(values: [Double]) -> NSImage {
        let size = NSSize(width: canvas, height: canvas)
        let count = values.count
        let cell = PixelEQ.cell
        let gapX = PixelEQ.gapX
        let pitchY = PixelEQ.pitchY
        let corner = PixelEQ.corner
        let blockWidth = CGFloat(count) * cell + CGFloat(count - 1) * gapX
        let startX = (canvas - blockWidth) / 2
        let centerY = canvas / 2

        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setFill()
            for (index, raw) in values.enumerated() {
                let litHalf = PixelEQ.litHalf(raw, maxHalf: 2)
                let x = startX + CGFloat(index) * (cell + gapX)
                for half in 0...litHalf {
                    let centers = half == 0
                        ? [centerY]
                        : [centerY - CGFloat(half) * pitchY, centerY + CGFloat(half) * pitchY]
                    for cy in centers {
                        let square = NSRect(x: x, y: cy - cell / 2, width: cell, height: cell)
                        NSBezierPath(roundedRect: square, xRadius: corner, yRadius: corner).fill()
                    }
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func image(cells: [Cell]) -> NSImage {
        let size = NSSize(width: canvas, height: canvas)
        let pitch = canvas / CGFloat(grid)
        let dot = pitch * 0.82
        let corner = dot * 0.28

        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setFill()
            for cell in cells {
                let originX = CGFloat(cell.col) * pitch + (pitch - dot) / 2
                let flippedRow = CGFloat(grid - 1 - cell.row)
                let originY = flippedRow * pitch + (pitch - dot) / 2
                let square = NSRect(x: originX, y: originY, width: dot, height: dot)
                NSBezierPath(roundedRect: square, xRadius: corner, yRadius: corner).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
