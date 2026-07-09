import Observation

@MainActor
@Observable
final class LiveWaveformModel {
    private(set) var samples: [Double]

    private var targetLevel: Double = 0
    private var displayedLevel: Double = 0

    init(sampleCount: Int) {
        samples = Array(repeating: 0, count: sampleCount)
    }

    func updateLevel(_ level: Double) {
        targetLevel = min(max(level, 0), 1)
    }

    func run() async {
        let clock = ContinuousClock()

        while !Task.isCancelled {
            advance()
            try? await clock.sleep(for: .milliseconds(33))
        }
    }

    private func advance() {
        let coefficient = targetLevel > displayedLevel ? 0.52 : 0.24
        displayedLevel += (targetLevel - displayedLevel) * coefficient

        samples.removeFirst()
        samples.append(displayedLevel)
    }
}
