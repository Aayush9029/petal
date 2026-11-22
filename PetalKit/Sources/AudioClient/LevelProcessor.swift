struct LevelProcessor {
    private var envelope: Double = 0
    private var ceiling: Double = LevelProcessor.minCeiling

    private static let attack: Double = 0.7
    private static let decay: Double = 0.18
    private static let gate: Double = 0.1
    private static let minCeiling: Double = 0.42
    private static let targetPeak: Double = 0.84
    private static let ceilingDecay: Double = 0.9985

    mutating func process(_ level: Double) -> Double {
        let clamped = max(0, min(1, level))
        let coefficient = clamped > envelope ? Self.attack : Self.decay
        envelope += (clamped - envelope) * coefficient
        let peakReference = envelope / Self.targetPeak
        ceiling = max(peakReference, ceiling * Self.ceilingDecay, Self.minCeiling)
        let normalized = (envelope - Self.gate) / (ceiling - Self.gate)
        return max(0, min(1, normalized))
    }

    static func normalizePower(_ power: Float) -> Double {
        // Built-in microphones meter conversational speech around -45 to -30 dBFS.
        max(0, min(1, (Double(power) + 58) / 40))
    }
}
