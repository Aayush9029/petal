import AVFoundation
import Foundation

public enum AudioImportError: LocalizedError {
    case unreadable

    public var errorDescription: String? { "Could not read the audio file." }
}

enum TranscriptionAudio {
    @concurrent
    static func importFile(from source: URL, to destination: URL) async throws {
        let input: AVAudioFile
        do {
            input = try AVAudioFile(forReading: source)
        } catch {
            throw AudioImportError.unreadable
        }
        let format = input.processingFormat
        let buffer = try buffer(format, frames: Int(min(format.sampleRate, 48_000)))
        let output = try AVAudioFile(forWriting: destination, settings: format.settings)
        do {
            while input.framePosition < input.length {
                try Task.checkCancellation()
                try input.read(into: buffer)
                guard buffer.frameLength > 0 else { break }
                try output.write(from: buffer)
            }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    @concurrent
    static func prepare(
        _ url: URL, trim: Bool, autoSpeed: Bool, onStage: @Sendable (TranscriptionStage) async -> Void
    ) async throws -> URL? {
        if trim { await onStage(.trimming) }
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = file.processingFormat
        let block = try buffer(format, frames: 16_384)
        var hasSignal = false
        var start = file.length
        var end: AVAudioFramePosition = 0
        while file.framePosition < file.length {
            try Task.checkCancellation()
            let offset = file.framePosition
            try file.read(into: block)
            guard block.frameLength > 0 else { break }
            for channel in 0..<Int(format.channelCount) {
                let samples = UnsafeBufferPointer(start: block.floatChannelData![channel], count: Int(block.frameLength))
                if !hasSignal { hasSignal = samples.contains { $0 != 0 } }
                if trim, let first = samples.firstIndex(where: { abs($0) > 0.003 }),
                   let last = samples.lastIndex(where: { abs($0) > 0.003 }) {
                    start = min(start, offset + Int64(first))
                    end = max(end, offset + Int64(last + 1))
                }
            }
            if !trim && hasSignal { break }
        }
        guard hasSignal else { return nil }
        let range = end - start > 1 ? start..<end : 0..<file.length
        let duration = Double(range.count) / format.sampleRate
        let rate = autoSpeed ? autoSpeedRate(for: duration) ?? 1 : 1
        guard range.count < file.length || rate > 1 else { return url }

        if rate > 1 { await onStage(.speeding) }
        let outputURL = FileManager.default.temporaryDirectory.appending(path: "petal-prepared-\(UUID()).wav")
        do {
            let output = try AVAudioFile(forWriting: outputURL, settings: format.settings)
            try write(file, range: range, rate: rate, to: output)
            return outputURL
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }

    private static func autoSpeedRate(for duration: Double) -> Double? {
        switch duration {
        case ..<45: nil
        case 45..<90: 1.1
        case 90..<180: 1.2
        default: 1.25
        }
    }

    private static func write(_ file: AVAudioFile, range: Range<AVAudioFramePosition>, rate: Double, to output: AVAudioFile) throws {
        let format = file.processingFormat
        let result = try buffer(format, frames: 8_192)
        let input = try buffer(format, frames: Int(ceil(Double(result.frameCapacity) * rate)) + 1)
        let frameCount = Int(Double(range.count) / rate)
        var written = 0
        while written < frameCount {
            try Task.checkCancellation()
            let count = min(frameCount - written, Int(result.frameCapacity))
            let first = Int(Double(written) * rate)
            file.framePosition = range.lowerBound + Int64(first)
            try file.read(into: input, frameCount: min(input.frameCapacity, AVAudioFrameCount(clamping: range.upperBound - file.framePosition)))
            guard input.frameLength > 0 else { throw AudioImportError.unreadable }
            let last = Int(input.frameLength) - 1
            for channel in 0..<Int(format.channelCount) {
                let samples = input.floatChannelData![channel]
                let destination = result.floatChannelData![channel]
                for index in 0..<count {
                    let position = Double(written + index) * rate - Double(first)
                    let left = min(Int(position), last)
                    let fraction = Float(position - Double(left))
                    destination[index] = samples[left] + fraction * (samples[min(left + 1, last)] - samples[left])
                }
            }
            result.frameLength = AVAudioFrameCount(count)
            try output.write(from: result)
            written += count
        }
    }

    private static func buffer(_ format: AVAudioFormat, frames: Int) throws -> AVAudioPCMBuffer {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(1, frames))) else {
            throw AudioImportError.unreadable
        }
        return buffer
    }
}
