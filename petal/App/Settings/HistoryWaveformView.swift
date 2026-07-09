import SwiftUI

struct HistoryWaveformView: View {
    let samples: [CGFloat]
    let progress: Double
    let onScrub: (Double) -> Void
    let onPlay: () -> Void

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let values = samples.isEmpty ? Array(repeating: CGFloat(0.12), count: 48) : samples
                let spacing: CGFloat = 2
                let barWidth = max(1, (size.width - spacing * CGFloat(values.count - 1)) / CGFloat(values.count))

                for (index, sample) in values.enumerated() {
                    let x = CGFloat(index) * (barWidth + spacing)
                    let height = max(2, sample * size.height)
                    let rect = CGRect(x: x, y: (size.height - height) / 2, width: barWidth, height: height)
                    let fraction = Double(index + 1) / Double(values.count)
                    let color = fraction <= progress ? Color.accentColor : Color.secondary.opacity(0.42)
                    context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(color))
                }
            }
            .contentShape(.rect)
            .onTapGesture(perform: onPlay)
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { value in
                        onScrub(max(0, min(1, value.location.x / max(proxy.size.width, 1))))
                    }
            )
        }
        .frame(height: 32)
        .accessibilityLabel("Recording waveform")
    }
}
