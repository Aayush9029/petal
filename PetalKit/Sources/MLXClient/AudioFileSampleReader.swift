import Shared

actor AudioFileSampleReader {
    private let samples: [Float]
    private var offset = 0

    init(samples: [Float]) {
        self.samples = samples
    }

    func next() -> [Float]? {
        guard offset < samples.count else { return nil }
        let end = min(offset + speechSampleRate, samples.count)
        defer { offset = end }
        return Array(samples[offset..<end])
    }
}
