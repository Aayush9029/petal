import AVFoundation
import Foundation
import Shared
import Testing
@testable import AudioClient

@Test
func streamingAudioPreservesOrderAndFlushesTheLastShortChunk() async throws {
    let producer = AudioSampleProducer()
    let samples = (0..<4_123).map(Float.init)
    producer.append(Array(samples[..<213]))
    producer.append(Array(samples[213..<2017]))
    producer.append(Array(samples[2017...]))
    producer.finish()
    producer.finish()
    producer.append([99])

    var chunks: [[Float]] = []
    for try await chunk in producer.stream { chunks.append(chunk) }
    #expect(chunks.map(\.count) == [1600, 1600, 923])
    #expect(chunks.flatMap { $0 } == samples)
}

@Test
func streamingAudioOverflowFailsInsteadOfReturningAnIncompleteRecording() async {
    let producer = AudioSampleProducer(bufferedChunks: 1)
    producer.append([Float](repeating: 1, count: 3200))
    producer.finish()
    do {
        for try await _ in producer.stream {}
        Issue.record("A dropped chunk must fail the stream so the saved audio can be retried")
    } catch AudioClientError.streamOverrun {
        // Expected: the app must not paste a transcript with missing audio.
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test
func streamingAudioCancellationDiscardsTheUnfinishedTail() async {
    let producer = AudioSampleProducer()
    producer.append([1, 2, 3])
    producer.finish(throwing: CancellationError())
    do {
        for try await _ in producer.stream { Issue.record("Cancelled audio must not be emitted") }
        Issue.record("Expected cancellation")
    } catch is CancellationError {} catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test
func realSpeechFixtureIsResampledWithoutLosingItsTail() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let url = root.appendingPathComponent("assets/e2e/conversational_a.wav")
    let input = try AVAudioFile(forReading: url)
    let samples = try AudioSampleProducer.readFixture(url)
    let expected = Double(input.length) * 16_000 / input.processingFormat.sampleRate
    #expect(abs(Double(samples.count) - expected) < 2)
    #expect(samples.allSatisfy { $0.isFinite })
    #expect(samples.contains { abs($0) > 0.01 })
}
