import CoreGraphics

public enum PixelEQ {
    public static let cell: CGFloat = 2.4
    public static let gapX: CGFloat = 1.5
    public static let pitchY: CGFloat = 3.0
    public static let cornerRatio: CGFloat = 0.3

    public static var corner: CGFloat { cell * cornerRatio }

    // Even buckets let quiet microphones reach each height.
    public static func litHalf(_ value: Double, maxHalf: Int) -> Int {
        let clamped = max(0, min(1, value))
        return min(maxHalf, Int(clamped * Double(maxHalf + 1)))
    }
}
