import SwiftUI

/// A continuously sampled microphone waveform. Its animation task is tied to
/// the view's lifetime instead of to the incoming level value, so frequent
/// observation updates cannot reset or stall the sampling cadence.
public struct LiveWaveform: View {
    private let level: Double
    private let bars: Int
    private let rows: Int
    private let tint: Color
    private let metrics: WaveformMetrics
    private let gain: Double
    private let responseExponent: Double
    private let sampleInterval: Duration

    @State private var model: LiveWaveformModel

    public init(
        level: Double,
        bars: Int = 13,
        maxHalf: Int = 2,
        tint: Color = .red
    ) {
        self.init(
            level: level,
            bars: bars,
            rows: maxHalf * 2 + 1,
            tint: tint,
            metrics: .standard,
            gain: 1,
            responseExponent: 1,
            sampleInterval: .milliseconds(52)
        )
    }

    public init(
        level: Double,
        bars: Int,
        rows: Int,
        tint: Color,
        sampleInterval: Duration = .milliseconds(52)
    ) {
        self.init(
            level: level,
            bars: bars,
            rows: rows,
            tint: tint,
            metrics: .standard,
            gain: 1,
            responseExponent: 1,
            sampleInterval: sampleInterval
        )
    }

    init(
        level: Double,
        bars: Int,
        rows: Int,
        tint: Color,
        metrics: WaveformMetrics,
        gain: Double,
        responseExponent: Double,
        sampleInterval: Duration
    ) {
        self.level = level
        self.bars = bars
        self.rows = rows
        self.tint = tint
        self.metrics = metrics
        self.gain = gain
        self.responseExponent = responseExponent
        self.sampleInterval = sampleInterval
        _model = State(initialValue: LiveWaveformModel(sampleCount: bars))
    }

    public var body: some View {
        Canvas { context, size in
            WaveformCanvasRenderer.draw(
                values: model.samples,
                rows: rows,
                tint: tint,
                metrics: metrics,
                in: context,
                size: size
            )
        }
        .frame(width: metrics.width(bars: bars), height: metrics.height(rows: rows))
        .onChange(of: level, initial: true) { _, newLevel in
            let clamped = min(max(newLevel, 0), 1)
            model.updateLevel(pow(clamped, responseExponent) * gain)
        }
        .task {
            await model.run(sampleInterval: sampleInterval)
        }
        .accessibilityLabel("Input level")
        .accessibilityValue(level < 0.08 ? "Quiet" : "Active")
    }
}

#if DEBUG
#Preview("Live Waveform") {
    VStack(spacing: 16) {
        LiveWaveform(level: 0.72)
        LiveWaveform(level: 0.55, bars: 46, maxHalf: 5)
    }
    .padding()
    .background(.black)
}
#endif
