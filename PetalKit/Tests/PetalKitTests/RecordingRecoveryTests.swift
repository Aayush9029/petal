import AVFoundation
import Foundation
import Testing
@testable import AudioClient

@Suite
struct RecordingRecoveryTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "petal-recovery-\(UUID().uuidString)")

    init() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    @Test
    func `a crashed WAV gets its sizes back and plays every frame`() throws {
        let url = directory.appending(path: "crashed.wav")
        let frames: AVAudioFrameCount = 22_050
        try writeWAV(to: url, frames: frames)
        try zeroSizes(of: url)
        #expect(throws: (any Error).self) { try AVAudioFile(forReading: url) }

        #expect(try WAVHeaderRepair.repair(url))

        #expect(try AVAudioFile(forReading: url).length == AVAudioFramePosition(frames))
        #expect(try !WAVHeaderRepair.repair(url))
    }

    @Test
    func `repair skips Apple's filler chunk before the data`() throws {
        let url = directory.appending(path: "filler.wav")
        let samples = Data(repeating: 0x10, count: 8_000)
        var header = Data("RIFF".utf8) + uint32(0) + Data("WAVE".utf8)
        header += Data("fmt ".utf8) + uint32(16) + uint16(1) + uint16(1) + uint32(16_000) + uint32(32_000) + uint16(2) + uint16(16)
        header += Data("FLLR".utf8) + uint32(4_000) + Data(count: 4_000)
        header += Data("data".utf8) + uint32(0)
        try (header + samples).write(to: url)

        #expect(try WAVHeaderRepair.repair(url))

        let repaired = try Data(contentsOf: url)
        #expect(repaired[4 ..< 8] == uint32(UInt32(repaired.count - 8)))
        #expect(repaired[header.count - 4 ..< header.count] == uint32(UInt32(samples.count)))
        #expect(try AVAudioFile(forReading: url).length == 4_000)
    }

    @Test
    func `the capture writer leaves a readable file when it never finishes`() async throws {
        let url = directory.appending(path: "abandoned.m4a")
        try await writeAbandonedRecording(to: url, seconds: 3)

        let file = try AVAudioFile(forReading: url)
        let seconds = Double(file.length) / file.processingFormat.sampleRate
        #expect(seconds > 1.5, "Only \(seconds) s survived")
    }

    @Test
    func `unfinished recordings skip active and empty files`() throws {
        let active = directory.appending(path: "petal-active.wav")
        let empty = directory.appending(path: "petal-empty.wav")
        let crashed = directory.appending(path: "petal-crashed.wav")
        let other = directory.appending(path: "notes.txt")
        try writeWAV(to: active, frames: 22_050)
        try writeWAV(to: empty, frames: 10)
        try writeWAV(to: crashed, frames: 22_050)
        try zeroSizes(of: crashed)
        try Data("hi".utf8).write(to: other)

        let unfinished = RecordingFiles.unfinished(in: directory, excluding: [active.standardizedFileURL])

        #expect(unfinished.map(\.lastPathComponent) == ["petal-crashed.wav"])
        #expect(!FileManager.default.fileExists(atPath: empty.path))
        #expect(try AVAudioFile(forReading: crashed).length == 22_050)
    }

    private func writeWAV(to url: URL, frames: AVAudioFrameCount) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames))
        buffer.frameLength = frames
        try file.write(from: buffer)
    }

    private func zeroSizes(of url: URL) throws {
        var data = try Data(contentsOf: url)
        data.replaceSubrange(4 ..< 8, with: uint32(0))
        let dataChunk = try #require(data.range(of: Data("data".utf8)))
        data.replaceSubrange(dataChunk.upperBound ..< dataChunk.upperBound + 4, with: uint32(0))
        try data.write(to: url)
    }

    private func writeAbandonedRecording(to url: URL, seconds: Int) async throws {
        let (writer, input) = try SelectedInputAudioRecording.makeWriter(outputURL: url)
        writer.add(input)
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 1, interleaved: false))
        var description = format.streamDescription.pointee
        var formatDescription: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(
            allocator: nil, asbd: &description, layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &formatDescription
        )
        let frames = 4_410
        for chunk in 0 ..< seconds * 10 {
            let pcm = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
            pcm.frameLength = AVAudioFrameCount(frames)
            for frame in 0 ..< frames {
                pcm.floatChannelData?[0][frame] = sin(Float(chunk * frames + frame) * 0.05) * 0.3
            }
            var timing = CMSampleTimingInfo(
                duration: CMTime(value: 1, timescale: 44_100),
                presentationTimeStamp: CMTime(value: CMTimeValue(chunk * frames), timescale: 44_100),
                decodeTimeStamp: .invalid
            )
            var sample: CMSampleBuffer?
            CMSampleBufferCreate(
                allocator: nil, dataBuffer: nil, dataReady: false, makeDataReadyCallback: nil, refcon: nil,
                formatDescription: formatDescription, sampleCount: frames, sampleTimingEntryCount: 1,
                sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample
            )
            let buffer = try #require(sample)
            CMSampleBufferSetDataBufferFromAudioBufferList(
                buffer, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, bufferList: pcm.audioBufferList
            )
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(1))
            }
            input.append(buffer)
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    private func uint32(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    private func uint16(_ value: UInt16) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }
}
