import SwiftUI

/// Fills a track over the threshold's own duration. Every card shares one wall-clock cycle and one absolute
/// track length, so a short hold visibly stops short of a long one instead of each filling its own width.
struct HoldDurationPreview: View {
    let seconds: Double
    let longestSeconds: Double
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let holdDuration: Double = 0.55
    private static let gapDuration: Double = 0.45

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            Canvas(opaque: false, rendersAsynchronously: false) { context, size in
                let radius = size.height / 2
                context.fill(
                    Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: radius),
                    with: .color(tint.opacity(0.18))
                )

                let width = size.width * fillFraction(at: timeline.date)
                guard width > 0 else { return }
                context.fill(
                    Path(roundedRect: CGRect(x: 0, y: 0, width: max(size.height, width), height: size.height), cornerRadius: radius),
                    with: .color(tint)
                )
            }
        }
        .frame(height: 6)
    }

    private var cycle: Double {
        longestSeconds + Self.holdDuration + Self.gapDuration
    }

    private var span: Double {
        longestSeconds > 0 ? min(1, seconds / longestSeconds) : 1
    }

    private func fillFraction(at date: Date) -> Double {
        guard !reduceMotion else { return span }
        let elapsed = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
        if elapsed <= seconds {
            return span * (seconds > 0 ? elapsed / seconds : 1)
        }
        return elapsed <= seconds + Self.holdDuration ? span : 0
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        HoldDurationPreview(seconds: 0.4, longestSeconds: 2, tint: .primary)
        HoldDurationPreview(seconds: 1.0, longestSeconds: 2, tint: .primary)
        HoldDurationPreview(seconds: 2.0, longestSeconds: 2, tint: .primary)
    }
    .frame(width: 180)
    .padding()
}
