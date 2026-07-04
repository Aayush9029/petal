import Combine
import SwiftUI

/// The dotted pixel waveform used by the floating capsule and the menu-bar
/// popover — the same grid as the menu-bar icon (`PixelEQ`), just wider.
///
/// Every column is a *real* level sample: while recording, the current input
/// level enters as the rightmost column and scrolls left, so speech carves
/// visible peaks and pauses carve flat stretches — the meter traces the voice
/// instead of faking a spectrum. In `.processing` a gentle self-animated pulse
/// is pushed instead, which reads as a traveling "working" wave; `.idle`
/// settles into a flat dotted line. Drawn in a single `Canvas`, composited on
/// the GPU.
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

    /// Level samples, oldest first; capped at `bars`.
    @State private var history: [Double] = []
    @State private var tick: Int = 0

    /// 20 Hz matches the ~60 ms cadence of the upstream level metering, so
    /// each column is a fresh sample and the scroll speed stays consistent.
    private let ticker = Timer.publish(every: 1.0 / 20.0, on: .main, in: .common).autoconnect()

    public init(_ mode: Mode, bars: Int = 13, maxHalf: Int = 2, tint: Color = .red) {
        self.mode = mode
        self.bars = bars
        self.maxHalf = maxHalf
        self.tint = tint
    }

    private var width: CGFloat { CGFloat(bars) * PixelEQ.pitchX }
    private var height: CGFloat { CGFloat(2 * maxHalf + 1) * PixelEQ.pitchY }

    /// The sample pushed into the history this frame.
    private func nextSample() -> Double {
        switch mode {
        case .idle:
            return 0.1
        case let .recording(level):
            // The level is already envelope-followed and auto-gained upstream;
            // push it straight through so the trace is honest.
            return max(0, min(1, level))
        case .processing:
            // Two detuned sines scrolling by produce an organic traveling wave.
            let t = Double(tick)
            return 0.45 + 0.28 * sin(t * 0.34) + 0.12 * sin(t * 0.81)
        }
    }

    /// History padded on the left so a fresh view starts as a flat line that
    /// the live trace scrolls into.
    private var displayValues: [Double] {
        if history.count >= bars {
            return Array(history.suffix(bars))
        }
        return Array(repeating: 0, count: bars - history.count) + history
    }

    public var body: some View {
        Canvas { context, size in
            let centerY = size.height / 2
            for (index, value) in displayValues.enumerated() {
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
            history.append(nextSample())
            if history.count > bars {
                history.removeFirst(history.count - bars)
            }
        }
    }
}

#if DEBUG
#Preview("Pixel Waveform") {
    VStack(spacing: 16) {
        PixelWaveform(.recording(level: 0.7))
        PixelWaveform(.processing, tint: .primary)
        PixelWaveform(.recording(level: 0.7), bars: 46, maxHalf: 5)
    }
    .padding()
    .background(.black)
}
#endif
