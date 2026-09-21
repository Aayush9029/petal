/// Ordered, owned 16 kHz mono Float32 PCM chunks. Finishing the stream marks
/// the end of captured audio; a consumer must drain it before finalizing ASR.
public typealias AudioSampleStream = AsyncThrowingStream<[Float], any Error>
