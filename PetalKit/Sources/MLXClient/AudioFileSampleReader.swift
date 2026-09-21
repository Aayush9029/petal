/// Feeds saved audio through the same streaming decoder used for microphone input.
/// Pulling one chunk at a time avoids a second, unbounded queue of the entire file.
actor AudioFileSampleReader {
    private let samples: [Float]
    private var offset = 0

    init(samples: [Float]) {
        self.samples = samples
    }

    func next() -> [Float]? {
        guard offset < samples.count else { return nil }
        let end = min(offset + 16_000, samples.count)
        defer { offset = end }
        return Array(samples[offset..<end])
    }
}
