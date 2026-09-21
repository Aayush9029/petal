import AVFoundation
import Foundation
import Shared

/// Confined to the capture queue. Only owned samples cross into the ASR task.
/// Thirty seconds of fixed-size chunks bounds memory while a cold model loads.
final class AudioSampleProducer {
    let stream: AudioSampleStream
    private let continuation: AudioSampleStream.Continuation
    private var pending: [Float] = []
    private var finished = false
    private static let chunkSize = 1600

    init(bufferedChunks: Int = 300) {
        (stream, continuation) = AudioSampleStream.makeStream(bufferingPolicy: .bufferingOldest(bufferedChunks))
    }

    func append(_ samples: [Float]) {
        guard !finished else { return }
        pending.append(contentsOf: samples)
        while pending.count >= Self.chunkSize, !finished {
            emit(Array(pending.prefix(Self.chunkSize)))
            pending.removeFirst(Self.chunkSize)
        }
    }

    func append(_ buffer: CMSampleBuffer) {
        guard !finished else { return }
        do {
            guard let description = buffer.formatDescription else { throw AudioClientError.invalidStreamFormat }
            let format = AVAudioFormat(cmAudioFormatDescription: description)
            guard format.sampleRate == 16_000, format.channelCount == 1,
                  format.commonFormat == .pcmFormatFloat32,
                  let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(buffer.numSamples)),
                  let samples = pcm.floatChannelData?[0]
            else { throw AudioClientError.invalidStreamFormat }
            pcm.frameLength = pcm.frameCapacity
            let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
                buffer, at: 0, frameCount: Int32(pcm.frameLength), into: pcm.mutableAudioBufferList
            )
            guard status == noErr else { throw AudioClientError.invalidStreamFormat }
            append(Array(UnsafeBufferPointer(start: samples, count: Int(pcm.frameLength))))
        } catch {
            finish(throwing: error)
        }
    }

    func finish(throwing error: (any Error)? = nil) {
        guard !finished else { return }
        if error == nil, !pending.isEmpty { emit(pending) }
        pending.removeAll()
        finished = true
        continuation.finish(throwing: error)
    }

    private func emit(_ samples: [Float]) {
        switch continuation.yield(samples) {
        case .enqueued: break
        case .dropped:
            // A partial transcript with missing audio must never be pasted as complete.
            finished = true
            continuation.finish(throwing: AudioClientError.streamOverrun)
        case .terminated:
            finished = true
        @unknown default:
            finished = true
            continuation.finish(throwing: AudioClientError.streamOverrun)
        }
    }

    /// Uses the same PCM contract for Petal's existing unattended speech fixtures.
    static func readFixture(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard file.length > 0, file.length < AVAudioFramePosition(UInt32.max),
              let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1),
              let converter = AVAudioConverter(from: file.processingFormat, to: format),
              let output = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(ceil(Double(file.length) * 16_000 / file.processingFormat.sampleRate)) + 1024
              )
        else { throw AudioClientError.invalidStreamFormat }
        try file.read(into: input)
        // The input block runs synchronously inside convert. A captured Mutex crashes the Swift 6.4 compiler.
        nonisolated(unsafe) var pendingInput: AVAudioPCMBuffer? = input
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            let buffer = pendingInput
            pendingInput = nil
            inputStatus.pointee = buffer == nil ? .endOfStream : .haveData
            return buffer
        }
        if let error { throw error }
        guard status != .error, let samples = output.floatChannelData?[0] else {
            throw AudioClientError.invalidStreamFormat
        }
        return Array(UnsafeBufferPointer(start: samples, count: Int(output.frameLength)))
    }
}
