import SwiftUI

struct RecordingBars: View {
    let level: Double

    @State private var samples = Array(repeating: 0.08, count: 16)
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 1.3) {
            ForEach(samples.indices, id: \.self) { index in
                Capsule()
                    .fill(.red.opacity(0.85))
                    .frame(width: 2.3, height: barHeight(for: samples[index], index: index))
            }
        }
        .frame(width: 58, height: 20)
        .onAppear {
            samples = seededSamples(from: level)
        }
        .onChange(of: level) { _, newValue in
            push(newValue)
        }
        .animation(.interactiveSpring(response: 0.16, dampingFraction: 0.78), value: samples)
    }

    private func push(_ level: Double) {
        var updated = samples
        updated.removeFirst()
        updated.append(normalizedSample(from: level))
        samples = updated
        phase += 1
    }

    private func seededSamples(from level: Double) -> [Double] {
        let sample = normalizedSample(from: level)
        return samples.indices.map { index in
            let wave = 0.72 + 0.28 * sin(CGFloat(index) * 0.86)
            return sample * Double(wave)
        }
    }

    private func normalizedSample(from level: Double) -> Double {
        let clamped = max(0, min(1, level))
        return max(0.05, pow(clamped, 0.55))
    }

    private func barHeight(for sample: Double, index: Int) -> CGFloat {
        let midpoint = CGFloat(samples.count - 1) / 2
        let distanceFromCenter = abs(CGFloat(index) - midpoint) / max(midpoint, 1)
        let centerBias = 1 - distanceFromCenter * 0.16
        let motion = 0.82 + 0.18 * sin(CGFloat(phase + index) * 0.78)
        return 3 + CGFloat(sample) * 16 * centerBias * motion
    }
}

#if DEBUG
#Preview("Recording Bars") {
    RecordingBars(level: 0.6)
        .padding()
}
#endif
