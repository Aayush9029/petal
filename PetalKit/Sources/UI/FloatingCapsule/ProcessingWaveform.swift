import SwiftUI

/// A seamless, deterministic working loop used while Petal processes audio.
/// Two counter-moving waves create a breathing ribbon without timers or
/// mutable per-frame state.
public struct ProcessingWaveform: View {
    private let bars: Int
    private let maxHalf: Int
    private let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(bars: Int = 13, maxHalf: Int = 2, tint: Color = .primary) {
        self.bars = bars
        self.maxHalf = maxHalf
        self.tint = tint
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let phase = reduceMotion ? 0 : loopPhase(at: timeline.date)
                WaveformCanvasRenderer.draw(
                    values: values(phase: phase),
                    opacities: opacities,
                    maxHalf: maxHalf,
                    tint: tint,
                    in: context,
                    size: size
                )
            }
        }
        .frame(width: PixelEQ.width(bars: bars), height: PixelEQ.height(maxHalf: maxHalf))
        .accessibilityLabel("Processing")
    }

    private var opacities: [Double] {
        (0..<bars).map { index in
            let position = Double(index) / Double(max(bars - 1, 1))
            return 0.32 + 0.68 * sin(.pi * position)
        }
    }

    private func values(phase: Double) -> [Double] {
        (0..<bars).map { index in
            let position = Double(index) / Double(max(bars - 1, 1))
            let centered = position * 2 - 1
            let envelope = 0.28 + 0.72 * pow(max(0, 1 - abs(centered)), 0.7)
            let forward = 0.5 + 0.5 * sin(phase + position * .pi * 2.4)
            let returnWave = 0.5 + 0.5 * sin(phase * 2 - position * .pi * 1.6 + 0.8)
            return min(1, 0.08 + envelope * (0.68 * forward + 0.18 * returnWave))
        }
    }

    private func loopPhase(at date: Date) -> Double {
        let duration = 2.8
        let progress = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: duration) / duration
        return progress * .pi * 2
    }
}

#if DEBUG
#Preview("Processing Waveform") {
    VStack(spacing: 16) {
        ProcessingWaveform()
        ProcessingWaveform(bars: 46, maxHalf: 5, tint: .accentColor)
    }
    .padding()
    .background(.black)
}
#endif
