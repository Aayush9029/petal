import AppKit
import UI

/// Draws the animated menu bar icon as a pixel grid into template `NSImage`s.
///
/// Everything is rendered on a 9×9 conceptual pixel grid mapped into an 18pt
/// square. Images are marked as template so the menu bar tints them for light
/// and dark appearances. Drawing is vector (rounded-rect cells), so it stays
/// crisp on Retina and is cheap enough to regenerate every animation frame.
enum MenuBarIconRenderer {
    static let grid = 9
    static let canvas: CGFloat = 18

    private static let center = CGPoint(x: 4, y: 4)

    /// Inset applied when redrawing the petal into the menu bar canvas. Kept
    /// small because the source artwork already carries ~10% internal margin;
    /// stacking a large inset on top made the glyph read smaller than adjacent
    /// SF Symbols.
    private static let contentInset: CGFloat = 0.02

    // MARK: - Idle petal

    /// The static pixel-petal, padded into the standard menu bar canvas.
    ///
    /// The raw `menuBarPetal` asset is 128pt and edge-to-edge, so the status
    /// item would otherwise scale it to the full bar height and read too large.
    /// We redraw it centered in an 18pt template with the same inset the
    /// animated frames use, so idle and active states share one visual size.
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

    // MARK: - Public frames

    /// A tiny audio-reactive pixel equalizer. The bars share the smoothed input
    /// power (which already carries a fast-attack / slow-decay envelope), shaped
    /// only by a fixed spatial profile with slight center emphasis — so they rise
    /// and fall together with loudness rather than flickering on their own.
    static func recording(level: Double) -> NSImage {
        // Preserve the approved icon geometry while giving speech more visual
        // headroom. The old linear response plus near-uniform profile pushed
        // all four bars to maximum height and read as a square blob.
        let power = pow(max(0, min(1, level)), 1.25) * 0.94
        return barsImage(values: recordingProfile.map { $0 * power })
    }

    /// The same equalizer, self-animated as a looping wave, for processing +
    /// downloads — reads as a steady "working" pulse without any audio input.
    static func working(tick: Int) -> NSImage {
        let values = (0..<barCount).map { index in
            0.5 + 0.5 * sin(Double(tick) * 0.3 + Double(index) * 1.1)
        }
        return barsImage(values: values)
    }

    /// Static pixel exclamation mark.
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

    // MARK: - Geometry

    private struct Cell { let col: Int; let row: Int }

    // MARK: - Equalizer bars

    private static let barCount = 4
    /// An asymmetric voice-like silhouette that stays legible at loud peaks.
    private static let recordingProfile: [Double] = [0.46, 0.78, 1.0, 0.6]

    /// Draws `values` (0...1) as symmetric pixel bars centered in the canvas,
    /// using the shared `PixelEQ` grid so it matches the capsule meter.
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
                let litHalf = PixelEQ.litHalf(raw, maxHalf: 2) // 0...2 → 1, 3 or 5 pixels tall
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

    // MARK: - Rasterization

    private static func image(cells: [Cell]) -> NSImage {
        let size = NSSize(width: canvas, height: canvas)
        let pitch = canvas / CGFloat(grid)
        let dot = pitch * 0.82
        let corner = dot * 0.28

        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setFill()
            for cell in cells {
                let originX = CGFloat(cell.col) * pitch + (pitch - dot) / 2
                // Flip row so row 0 is visually at the top.
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
