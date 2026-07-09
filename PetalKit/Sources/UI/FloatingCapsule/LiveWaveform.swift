import SwiftUI

/// A continuously sampled microphone waveform. Its animation task is tied to
/// the view's lifetime instead of to the incoming level value, so frequent
/// observation updates cannot reset or stall the sampling cadence.
public struct LiveWaveform: View {
    private let level: Double
    private let bars: Int
    private let maxHalf: Int
    private let tint: Color

    @State private var model: LiveWaveformModel

    public init(
        level: Double,
        bars: Int = 13,
        maxHalf: Int = 2,
        tint: Color = .red
    ) {
        self.level = level
        self.bars = bars
        self.maxHalf = maxHalf
        self.tint = tint
        _model = State(initialValue: LiveWaveformModel(sampleCount: bars))
    }

    public var body: some View {
        Canvas { context, size in
            WaveformCanvasRenderer.draw(
                values: model.samples,
                maxHalf: maxHalf,
                tint: tint,
                in: context,
                size: size
            )
        }
        .frame(width: PixelEQ.width(bars: bars), height: PixelEQ.height(maxHalf: maxHalf))
        .onChange(of: level, initial: true) { _, newLevel in
            model.updateLevel(newLevel)
        }
        .task {
            await model.run()
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
