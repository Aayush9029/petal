import Combine
import SwiftUI

/// The floating-capsule pixel equalizer — the same grid as the menu-bar icon
/// (`PixelEQ`), just wider.
///
/// Bars have *varied* heights (a slowly shifting spectrum profile) so it reads
/// as a lively equalizer rather than a solid block. In `.recording` the overall
/// amplitude tracks your voice; in `.processing` it holds a calm, low amplitude.
/// Drawn in a single `Canvas`, composited on the GPU.
public struct PixelWaveform: View {
    public enum Mode: Equatable {
        case idle
        case recording(level: Double)
        case processing
    }

    let mode: Mode
    var bars: Int = 13
    var maxHalf: Int = 2
    var tint: Color = .red

    @State private var smoothed: Double = 0
    @State private var tick: Int = 0

    private let ticker = Timer.publish(every: 1.0 / 20.0, on: .main, in: .common).autoconnect()

    public init(_ mode: Mode, bars: Int = 13, maxHalf: Int = 2, tint: Color = .red) {
        self.mode = mode
        self.bars = bars
        self.maxHalf = maxHalf
        self.tint = tint
    }

    private var width: CGFloat { CGFloat(bars) * PixelEQ.pitchX }
    private var height: CGFloat { CGFloat(2 * maxHalf + 1) * PixelEQ.pitchY }

    /// A normalized 0…1 "spectrum" weight for a bar, shifting slowly over time so
    /// the shape stays alive. This is what gives the bars their varied heights.
    private func profile(_ index: Int) -> Double {
        let t = Double(tick)
        let a = sin(Double(index) * 0.85 + t * 0.16)
        let b = sin(Double(index) * 1.7 - t * 0.11)
        return 0.35 + 0.65 * (0.5 + 0.5 * (a * 0.6 + b * 0.4))
    }

    /// The value (0…1) for each bar this frame.
    private var barValues: [Double] {
        // Recording amplitude follows the voice; processing holds a calm level.
        let amplitude: Double
        switch mode {
        case .idle:
            amplitude = 0.26
        case .recording:
            amplitude = min(1, smoothed * 1.15)
        case .processing:
            amplitude = 0.5
        }
        return (0..<bars).map { amplitude * profile($0) }
    }

    public var body: some View {
        Canvas { context, size in
            let centerY = size.height / 2
            for (index, value) in barValues.enumerated() {
                let litHalf = PixelEQ.litHalf(value, maxHalf: maxHalf)
                let x = CGFloat(index) * PixelEQ.pitchX
                for half in 0...litHalf {
                    let centers = half == 0
                        ? [centerY]
                        : [centerY - CGFloat(half) * PixelEQ.pitchY, centerY + CGFloat(half) * PixelEQ.pitchY]
                    for cy in centers {
                        let rect = CGRect(x: x, y: cy - PixelEQ.cell / 2, width: PixelEQ.cell, height: PixelEQ.cell)
                        context.fill(
                            Path(roundedRect: rect, cornerRadius: PixelEQ.corner),
                            with: .color(tint)
                        )
                    }
                }
            }
        }
        .frame(width: width, height: height)
        .onReceive(ticker) { _ in
            tick &+= 1
            if case let .recording(level) = mode {
                // The level is already envelope-followed upstream; a light smooth
                // keeps the amplitude from stepping harshly.
                smoothed = smoothed * 0.25 + pow(max(0, min(1, level)), 0.6) * 0.75
            }
        }
    }
}

#if DEBUG
#Preview("Pixel Waveform") {
    VStack(spacing: 16) {
        PixelWaveform(.recording(level: 0.7))
        PixelWaveform(.processing, tint: .primary)
    }
    .padding()
    .background(.black)
}
#endif
