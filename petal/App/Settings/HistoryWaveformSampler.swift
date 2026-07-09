import AVFAudio
import SwiftUI

enum HistoryWaveformSampler {
    nonisolated static func samples(from url: URL, count: Int = 64) async -> [CGFloat] {
        let task: Task<[CGFloat], Never> = Task.detached(priority: .utility) {
            guard count > 0,
                  let file = try? AVAudioFile(forReading: url),
                  file.length > 0,
                  let buffer = AVAudioPCMBuffer(
                      pcmFormat: file.processingFormat,
                      frameCapacity: 4096
                  )
            else {
                return []
            }

            var peaks = Array(repeating: Float.zero, count: count)
            let totalFrames = max(Int64(file.length), 1)
            var processedFrames: Int64 = 0

            while processedFrames < totalFrames {
                guard !Task.isCancelled else { return [] }

                do {
                    try file.read(into: buffer, frameCount: buffer.frameCapacity)
                } catch {
                    return []
                }

                let frameCount = Int(buffer.frameLength)
                guard frameCount > 0, let channels = buffer.floatChannelData else { break }
                let channelCount = Int(buffer.format.channelCount)

                for frame in 0 ..< frameCount {
                    if frame.isMultiple(of: 512), Task.isCancelled {
                        return []
                    }

                    let absoluteFrame = processedFrames + Int64(frame)
                    let bucket = min(count - 1, Int(absoluteFrame * Int64(count) / totalFrames))
                    var peak = Float.zero
                    for channel in 0 ..< channelCount {
                        peak = max(peak, abs(channels[channel][frame]))
                    }
                    peaks[bucket] = max(peaks[bucket], peak)
                }

                processedFrames += Int64(frameCount)
            }

            let maximum = max(peaks.max() ?? 0, 0.001)
            return peaks.map { peak in
                let normalized = Double(peak / maximum)
                return CGFloat(max(0.08, pow(normalized, 0.55)))
            }
        }

        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
