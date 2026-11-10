import SwiftUI

/// A dim waveform silhouette that fills from the left as a download progresses.
public struct DownloadWaveform: View {
    private let progress: Double?
    private let isPaused: Bool
    private let bars: Int
    private let rows: Int
    private let tint: Color
    private let metrics: WaveformMetrics

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let ghostOpacity = 0.16
    private static let filledOpacity = 0.62
    private static let shimmerWidth = 9.0
    private static let shimmerPeriod = 1.9

    /// A nil `progress` means the size is not known yet.
    public init(progress: Double?, isPaused: Bool = false, bars: Int, rows: Int, tint: Color = .accentColor) {
        self.progress = progress.map { min(max($0, 0), 1) }
        self.isPaused = isPaused
        self.bars = bars
        self.rows = rows
        self.tint = tint
        metrics = .standard
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: isPaused || reduceMotion)) { timeline in
            Canvas { context, size in
                let isStill = isPaused || reduceMotion
                draw(time: isStill ? nil : timeline.date.timeIntervalSinceReferenceDate, in: context, size: size)
            }
        }
        .frame(width: metrics.width(bars: bars), height: metrics.height(rows: rows))
        .accessibilityElement()
        .accessibilityLabel(isPaused ? "Download paused" : "Downloading")
        .accessibilityValue(progress.map { Text($0, format: .percent.precision(.fractionLength(0))) } ?? Text(""))
    }

    private func draw(time: Double?, in context: GraphicsContext, size: CGSize) {
        guard bars > 0, rows > 0 else { return }
        let originX = (size.width - metrics.width(bars: bars)) / 2
        let centerY = size.height / 2
        let filled = (progress ?? 0) * Double(bars)
        let cellSize = CGSize(width: metrics.cell, height: metrics.cell)
        let corner = CGSize(width: metrics.corner, height: metrics.corner)
        let maxHalf = (rows - 1) / 2

        // The band sweeps the filled part, or the whole width while the size is unknown.
        let sweepSpan = (progress == nil ? Double(bars) : filled) + Self.shimmerWidth * 2
        let shimmerCenter = time.map {
            $0.truncatingRemainder(dividingBy: Self.shimmerPeriod) / Self.shimmerPeriod * sweepSpan - Self.shimmerWidth
        }

        for bar in 0 ..< bars {
            let half = PixelEQ.litHalf(Self.silhouette(bar), maxHalf: maxHalf)
            var path = Path()
            for row in -half ... half {
                let origin = CGPoint(
                    x: originX + CGFloat(bar) * metrics.pitchX,
                    y: centerY + CGFloat(row) * metrics.pitchY - metrics.cell / 2
                )
                path.addRoundedRect(in: CGRect(origin: origin, size: cellSize), cornerSize: corner)
            }

            let coverage = min(max(filled - Double(bar), 0), 1)
            var opacity = Self.ghostOpacity + (Self.filledOpacity - Self.ghostOpacity) * coverage
            if let shimmerCenter, progress == nil || coverage > 0 {
                let distance = abs(Double(bar) - shimmerCenter) / Self.shimmerWidth
                let glow = distance < 1 ? pow(cos(distance * .pi / 2), 2) : 0
                opacity += (1 - opacity) * glow * (progress == nil ? 0.6 : 1)
            }
            context.fill(path, with: .color(tint.opacity(opacity)))
        }
    }

    /// A fixed speech-like outline, so the shape does not move while it fills.
    private static func silhouette(_ bar: Int) -> Double {
        let x = Double(bar)
        let envelope = abs(sin(x * 0.21 + 0.6) * cos(x * 0.057 + 0.2))
        let detail = 0.5 + 0.5 * sin(x * 0.83 + 1.1)
        return min(1, 0.12 + 0.72 * envelope + 0.22 * detail * envelope)
    }
}

#if DEBUG
#Preview("Download Waveform") {
    VStack(spacing: 16) {
        DownloadWaveform(progress: nil, bars: 69, rows: 17)
        DownloadWaveform(progress: 0.35, bars: 69, rows: 17)
        DownloadWaveform(progress: 0.8, isPaused: true, bars: 69, rows: 17)
    }
    .padding()
    .background(.black)
}
#endif
