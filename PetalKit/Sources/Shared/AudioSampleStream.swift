package let speechSampleRate = 16_000

/// Consumers drain the mono PCM stream before finalizing recognition.
public typealias AudioSampleStream = AsyncThrowingStream<[Float], any Error>
