import SwiftUI

/// A seamless, deterministic working loop used while Petal processes audio.
/// Two counter-moving waves create a breathing ribbon without timers or
/// mutable per-frame state.
public struct ProcessingWaveform: View {
    private let bars: Int
    private let rows: Int
    private let tint: Color
    private let metrics: WaveformMetrics

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(bars: Int = 13, maxHalf: Int = 2, tint: Color = .primary) {
        self.init(bars: bars, rows: maxHalf * 2 + 1, tint: tint, metrics: .standard)
    }

    public init(bars: Int, rows: Int, tint: Color) {
        self.init(bars: bars, rows: rows, tint: tint, metrics: .standard)
    }

    init(bars: Int, rows: Int, tint: Color, metrics: WaveformMetrics) {
        self.bars = bars
        self.rows = rows
        self.tint = tint
        self.metrics = metrics
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let phase = reduceMotion ? 0 : loopPhase(at: timeline.date)
                WaveformCanvasRenderer.drawHelix(
                    phase: phase,
                    bars: bars,
                    rows: rows,
                    tint: tint,
                    metrics: metrics,
                    in: context,
                    size: size
                )
            }
        }
        .frame(width: metrics.width(bars: bars), height: metrics.height(rows: rows))
        .accessibilityLabel("Processing")
    }

    private func loopPhase(at date: Date) -> Double {
        let duration = 2.4
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
