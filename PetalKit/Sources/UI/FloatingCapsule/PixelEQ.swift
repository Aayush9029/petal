import CoreGraphics

/// Shared spec for the pixel equalizer used by both the menu-bar icon
/// (AppKit `NSImage`) and the floating capsule meter (SwiftUI `Canvas`).
///
/// Keeping the metrics in one place is what makes the two renderers read as the
/// *same* grid — chunky square cells, tight gaps, rounded corners, and heights
/// quantized into symmetric odd steps (1, 3, 5, 7 … cells). The absolute values
/// are the menu-bar grid the user approved; the capsule reuses them at a larger
/// bar/row count so it looks like the same grid, just wider.
public enum PixelEQ {
    /// Side length of one square pixel cell.
    public static let cell: CGFloat = 2.4
    /// Horizontal gap between bars.
    public static let gapX: CGFloat = 1.5
    /// Vertical distance between stacked cell centers.
    public static let pitchY: CGFloat = 3.0
    /// Corner radius as a fraction of `cell`.
    public static let cornerRatio: CGFloat = 0.3

    /// Center-to-center horizontal pitch of adjacent bars.
    public static var pitchX: CGFloat { cell + gapX }
    /// Corner radius for a cell.
    public static var corner: CGFloat { cell * cornerRatio }

    /// Number of lit half-rows above/below the center for a `0…1` value, given
    /// the maximum half-rows available. `0 → just the center cell`, producing
    /// symmetric bars of 1, 3, 5 … cells.
    public static func litHalf(_ value: Double, maxHalf: Int) -> Int {
        let clamped = max(0, min(1, value))
        return Int((clamped * Double(maxHalf)).rounded())
    }
}
