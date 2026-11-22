@preconcurrency import AVFoundation
import Foundation

enum HistoryAudioCompressionProfile: Sendable {
    case standard
    case aggressive

    private var sampleRate: Double {
        switch self {
        case .standard: 22_050
        case .aggressive: 16_000
        }
    }

    private var bitRate: Int {
        switch self {
        case .standard: 64_000
        case .aggressive: 24_000
        }
    }

    @concurrent
    func encode(
        from source: URL,
        to destination: URL
    ) async throws {
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw NSError(
                domain: "HistoryClient",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "No audio track found for history export"]
            )
        }

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
        )
        readerOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(readerOutput) else {
            throw NSError(
                domain: "HistoryClient",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Cannot add audio track output for history export"]
            )
        }
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: destination, fileType: .m4a)
        let writerInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: self.sampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: self.bitRate
            ]
        )
        writerInput.expectsMediaDataInRealTime = false

        guard writer.canAdd(writerInput) else {
            throw NSError(
                domain: "HistoryClient",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Cannot add audio writer input for history export"]
            )
        }
        writer.add(writerInput)

        guard writer.startWriting() else {
            throw writer.error ?? NSError(
                domain: "HistoryClient",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Unable to start history audio writer"]
            )
        }
        guard reader.startReading() else {
            writer.cancelWriting()
            throw reader.error ?? NSError(
                domain: "HistoryClient",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Unable to start history audio reader"]
            )
        }

        writer.startSession(atSourceTime: .zero)

        while reader.status == .reading {
            if !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(2))
                continue
            }

            guard let sampleBuffer = readerOutput.copyNextSampleBuffer() else { break }
            guard writerInput.append(sampleBuffer) else {
                reader.cancelReading()
                writer.cancelWriting()
                throw writer.error ?? reader.error ?? NSError(
                    domain: "HistoryClient",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Failed appending sample buffer during history export"]
                )
            }
        }

        if reader.status == .failed {
            writer.cancelWriting()
            throw reader.error ?? NSError(
                domain: "HistoryClient",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "History audio reader failed during export"]
            )
        }

        writerInput.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed {
            throw writer.error ?? NSError(
                domain: "HistoryClient",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "History audio writer failed during export"]
            )
        }
    }
}
