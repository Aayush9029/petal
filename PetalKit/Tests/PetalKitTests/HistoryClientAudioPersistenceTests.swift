import AVFoundation
import Foundation
import Shared
import Testing
@testable import HistoryClient

extension HistoryFolderSuite {
    @Suite("History audio persistence")
    struct HistoryAudioPersistenceTests {
        @Test
        func historyAudioDefaultProfileExportsAACM4A() async throws {
            let inputURL = try writeAudioFixture(durationSeconds: 6)
            defer { try? FileManager.default.removeItem(at: inputURL) }

            let historyClient = HistoryClient.liveValue
            let outputURL = try await persistHistoryAudio(
                historyClient: historyClient,
                audioURL: inputURL,
                compressAudio: false
            )
            defer { try? FileManager.default.removeItem(at: outputURL) }

            #expect(outputURL.pathExtension.lowercased() == "m4a")
            let file = try AVAudioFile(forReading: outputURL)
            #expect(file.fileFormat.streamDescription.pointee.mFormatID == kAudioFormatMPEG4AAC)
            #expect(file.length > 0)
        }

        @Test
        func historyAudioAggressiveProfileProducesSmallerFile() async throws {
            let inputURL = try writeAudioFixture(durationSeconds: 20)
            defer { try? FileManager.default.removeItem(at: inputURL) }

            let historyClient = HistoryClient.liveValue

            let standardOutputURL = try await persistHistoryAudio(
                historyClient: historyClient,
                audioURL: inputURL,
                compressAudio: false
            )
            defer { try? FileManager.default.removeItem(at: standardOutputURL) }

            let compressedOutputURL = try await persistHistoryAudio(
                historyClient: historyClient,
                audioURL: inputURL,
                compressAudio: true
            )
            defer { try? FileManager.default.removeItem(at: compressedOutputURL) }

            let standardSize = try fileSize(of: standardOutputURL)
            let compressedSize = try fileSize(of: compressedOutputURL)

            #expect(compressedSize < standardSize)
        }

        @Test
        func sessionsThatFinishInTheSameSecondKeepIndependentArtifacts() async throws {
            let input = try writeAudioFixture(durationSeconds: 2)
            defer { try? FileManager.default.removeItem(at: input) }
            let history = HistoryClient.liveValue
            let timestamp = Date()
            let modelID = UUID().uuidString
            var days: [TranscriptHistoryDay] = []
            defer {
                for id in days.flatMap(\.entries).map(\.id) {
                    days = history.deleteEntry(days, id)
                }
            }

            for text in ["first take", "second take"] {
                let saved = await history.persistArtifacts(.init(
                    audioURL: input, transcript: text, timestamp: timestamp, mode: "verbatim",
                    modelID: modelID, retentionMode: .both
                ))
                let artifacts = try #require(saved)
                days = history.appendEntry(.init(
                    currentDays: days, transcript: text, modelID: modelID, mode: "verbatim",
                    audioDuration: 2, transcriptionElapsed: 1, pasteResult: "copied",
                    audioRelativePath: artifacts.audioRelativePath, transcriptRelativePath: artifacts.transcriptRelativePath,
                    retentionMode: .both, timestamp: timestamp, sessionID: UUID()
                ))
            }

            let entries = days.flatMap(\.entries)
            let first = try #require(entries.first { history.transcriptText($0.preferredTranscriptRelativePath) == "first take" })
            let second = try #require(entries.first { history.transcriptText($0.preferredTranscriptRelativePath) == "second take" })
            #expect(history.historyAudioURL(first.audioRelativePath) != nil)
            days = history.deleteEntry(days, first.id)
            #expect(days.flatMap(\.entries).map(\.id) == [second.id])
            #expect(history.historyAudioURL(first.audioRelativePath) == nil)
            #expect(history.transcriptText(first.preferredTranscriptRelativePath) == nil)
            #expect(history.historyAudioURL(second.audioRelativePath) != nil)
            #expect(history.transcriptText(second.preferredTranscriptRelativePath) == "second take")
        }

        @Test
        func enablingTranscriptsKeepsExistingAudioOnlyRecordingsAndTheirSharedFiles() async throws {
            let input = try writeAudioFixture(durationSeconds: 2)
            defer { try? FileManager.default.removeItem(at: input) }
            let history = HistoryClient.liveValue
            let saved = await history.persistArtifacts(.init(
                audioURL: input, transcript: "", timestamp: Date(), mode: "verbatim",
                modelID: "fixture", retentionMode: .audio
            ))
            let path = try #require(saved?.audioRelativePath)
            let audio = try #require(history.historyAudioURL(path))
            defer { try? FileManager.default.removeItem(at: audio) }
            let first = UUID()
            let second = UUID()
            var days: [TranscriptHistoryDay] = []
            for id in [first, second] {
                days = history.appendEntry(.init(
                    currentDays: days, transcript: "", modelID: "fixture", mode: "verbatim",
                    audioDuration: 2, transcriptionElapsed: 1, pasteResult: "skipped",
                    audioRelativePath: path, transcriptRelativePath: nil,
                    retentionMode: .audio, timestamp: Date(), sessionID: id
                ))
            }

            days = history.applyRetention(.both, days)
            #expect(Set(days.flatMap(\.entries).map(\.id)) == [first, second])
            days = history.deleteEntry(days, first)
            let remaining = try #require(days.flatMap(\.entries).first)
            #expect(remaining.id == second)
            #expect(history.historyAudioURL(remaining.audioRelativePath) == audio)
            #expect(history.deleteEntry(days, second).isEmpty)
            #expect(history.historyAudioURL(path) == nil)
        }

        @Test
        func historyDoesNotCapEntriesWithinADay() throws {
            let historyClient = HistoryClient.liveValue
            let timestamp = try #require(Calendar.current.date(from: DateComponents(year: 2024, month: 6, day: 1, hour: 12)))
            var days: [TranscriptHistoryDay] = []

            for index in 0 ..< 250 {
                days = historyClient.appendEntry(
                    AppendEntryRequest(
                        currentDays: days,
                        transcript: "Transcript \(index)",
                        modelID: "test-model",
                        mode: "verbatim",
                        audioDuration: 1,
                        transcriptionElapsed: 1,
                        pasteResult: "skipped",
                        audioRelativePath: nil,
                        transcriptRelativePath: nil,
                        retentionMode: .both,
                        timestamp: timestamp.addingTimeInterval(Double(index)),
                        sessionID: UUID()
                    )
                )
            }

            #expect(days.count == 1)
            #expect(days.first?.entries.count == 250)
        }
    }
}

private func persistHistoryAudio(
    historyClient: HistoryClient,
    audioURL: URL,
    compressAudio: Bool
) async throws -> URL {
    guard let artifacts = await historyClient.persistArtifacts(
        PersistArtifactsRequest(
            audioURL: audioURL,
            transcript: "fixture transcript",
            timestamp: Date(),
            mode: "verbatim",
            modelID: "history-test-\(UUID().uuidString)",
            retentionMode: .audio,
            compressAudio: compressAudio,
            persistAudio: true
        )
    ) else {
        throw HistoryAudioPersistenceTestError.persistFailed
    }

    guard let relativePath = artifacts.audioRelativePath else {
        throw HistoryAudioPersistenceTestError.missingRelativePath
    }

    guard let outputURL = historyClient.historyAudioURL(relativePath) else {
        throw HistoryAudioPersistenceTestError.missingOutputURL
    }

    return outputURL
}

private func writeAudioFixture(durationSeconds: Double) throws -> URL {
    let sampleRate = 44_100.0
    let frameCount = Int(sampleRate * durationSeconds)
    let samples = makeSpeechLikeSamples(count: frameCount, sampleRate: sampleRate)

    let url = FileManager.default.temporaryDirectory
        .appending(path: "history-audio-fixture-\(UUID().uuidString).wav")

    guard let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: false
    ) else {
        throw HistoryAudioPersistenceTestError.invalidFormat
    }

    guard let buffer = AVAudioPCMBuffer(
        pcmFormat: format,
        frameCapacity: AVAudioFrameCount(samples.count)
    ) else {
        throw HistoryAudioPersistenceTestError.bufferCreationFailed
    }

    buffer.frameLength = AVAudioFrameCount(samples.count)
    guard let channelData = buffer.floatChannelData?[0] else {
        throw HistoryAudioPersistenceTestError.bufferCreationFailed
    }

    for (index, sample) in samples.enumerated() {
        channelData[index] = sample
    }

    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
    return url
}

private func makeSpeechLikeSamples(count: Int, sampleRate: Double) -> [Float] {
    var samples: [Float] = []
    samples.reserveCapacity(count)

    var seed: UInt64 = 0xA57C_9E23_11D4_5B7A

    for index in 0..<count {
        let time = Double(index) / sampleRate

        seed = seed &* 6364136223846793005 &+ 1
        let noiseComponent = Float((Double((seed >> 33) & 0xFFFF) / Double(0xFFFF)) - 0.5) * 0.05

        let envelope = Float((sin(2 * .pi * 1.9 * time) + 1) * 0.5)
        let voicedComponent =
            0.55 * sin(2 * .pi * 165 * time) +
            0.28 * sin(2 * .pi * 330 * time) +
            0.17 * sin(2 * .pi * 510 * time)

        let sample = Float(voicedComponent) * (0.2 + (0.8 * envelope)) + noiseComponent
        samples.append(max(-1, min(1, sample)))
    }

    return samples
}

private func fileSize(of url: URL) throws -> Int64 {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return attributes[.size] as? Int64 ?? 0
}

private enum HistoryAudioPersistenceTestError: Error {
    case persistFailed
    case missingRelativePath
    case missingOutputURL
    case invalidFormat
    case bufferCreationFailed
}
