import AudioClient
import CustomDump
import DependenciesTestSupport
import Foundation
import FoundationModelClient
import HistoryClient
import LogClient
import PasteClient
import Shared
import SoundClient
import Testing
import TranscriptionClient
@testable import AppFeature

@MainActor
@Suite(.dependencies {
    $0.date = .constant(Date(timeIntervalSince1970: 2_000_000))
    $0.uuid = .incrementing
    $0.continuousClock = ImmediateClock()
    $0.soundClient.play = { _ in }
    $0.transcriptionClient.audioDurationSeconds = { _ in 10 }
    $0.transcriptionClient.importAudio = { _, _ in }
    $0.transcriptionClient.transcribe = { _, _, _ in "some words" }
    $0.notificationClient.post = { _ in }
})
struct AppFeatureTranscriptionTests {
    @Test
    func `another drop cannot take over a history reprocessing request during capture preflight`() async throws {
        let gate = AsyncGate()
        let preflights = LockIsolated(0)
        let commits = LockIsolated<[AppendEntryRequest]>([])
        let entry = historyEntry()
        let model = withDependencies {
            $0.audioClient.isRecording = {
                let first = preflights.withValue { count in
                    count += 1
                    return count == 1
                }
                if first { await gate.wait() }
                return false
            }
            $0.historyClient.historyAudioURL = { _ in URL.temporaryDirectory.appending(path: "original.wav") }
            $0.historyClient.persistArtifacts = { _ in PersistedArtifacts(transcriptRelativePath: "transcripts/new.txt") }
            $0.historyClient.appendEntry = { request in
                commits.withValue { $0.append(request) }
                return request.currentDays
            }
        } operation: {
            makeModel(with: entry)
        }

        let reprocessing = Task { await model.reprocessTranscriptHistoryButtonTapped(entry.id, cleansUp: false) }
        await gate.waitUntilWaiting()
        await model.audioFilesDropped([URL.temporaryDirectory.appending(path: "other.wav")])
        await gate.open()
        await reprocessing.value

        #expect(preflights.value == 1)
        #expect(commits.value.count == 1)
        let saved = try #require(commits.value.first)
        #expect(saved.sessionID == entry.id)
        #expect(saved.timestamp == entry.timestamp)
        #expect(saved.replacesVariants)
    }

    @Test
    func `a failed original variant leaves the previous history and discards the staged cleanup`() async {
        let discarded = LockIsolated<[String?]>([])
        let entry = historyEntry()
        let model = withDependencies {
            $0.historyClient.historyAudioURL = { _ in URL.temporaryDirectory.appending(path: "archive.m4a") }
            $0.historyClient.persistArtifacts = { request in
                request.mode == TranscriptHistoryVariant.originalMode
                    ? nil
                    : PersistedArtifacts(transcriptRelativePath: "transcripts/staged.txt")
            }
            $0.historyClient.discardArtifacts = { paths in discarded.withValue { $0.append(paths.transcriptRelativePath) } }
            $0.foundationModelClient.isAvailable = { true }
            $0.foundationModelClient.refine = { _, _ in "Some words." }
        } operation: {
            makeModel(with: entry)
        }
        model.$cleanupModel.withLock { $0 = .appleIntelligence }
        let previousHistory = model.transcriptHistoryDays

        await model.reprocessTranscriptHistoryButtonTapped(entry.id, cleansUp: true)

        expectNoDifference(model.transcriptHistoryDays, previousHistory)
        expectNoDifference(discarded.value, ["transcripts/staged.txt"])
    }

    @Test
    func `deleting an entry during reprocessing discards the replacement`() async {
        let gate = AsyncGate()
        let discarded = LockIsolated<[String?]>([])
        let entry = historyEntry()
        let model = withDependencies {
            $0.historyClient.historyAudioURL = { _ in URL.temporaryDirectory.appending(path: "archive.m4a") }
            $0.historyClient.persistArtifacts = { _ in
                await gate.wait()
                return PersistedArtifacts(transcriptRelativePath: "transcripts/replacement.txt")
            }
            $0.historyClient.discardArtifacts = { paths in discarded.withValue { $0.append(paths.transcriptRelativePath) } }
            $0.historyClient.deleteEntry = { _, _ in [] }
        } operation: {
            makeModel(with: entry)
        }

        let reprocessing = Task { await model.reprocessTranscriptHistoryButtonTapped(entry.id, cleansUp: false) }
        await gate.waitUntilWaiting()
        model.deleteTranscriptHistoryButtonTapped(entry.id)
        await gate.open()
        await reprocessing.value

        #expect(model.transcriptHistoryDays.isEmpty)
        expectNoDifference(discarded.value, ["transcripts/replacement.txt"])
    }

    @Test(arguments: [false, true])
    func `recovery tries an unfinished recording once, so a bad file cannot fail at every launch`(decoderFails: Bool) async throws {
        let audio = URL.temporaryDirectory.appending(path: UUID().uuidString).appendingPathExtension("wav")
        let bytes = Data([0, 0])
        try bytes.write(to: audio)
        defer { try? FileManager.default.removeItem(at: audio) }
        let copies = LockIsolated<[String]>([])
        let message = await withDependencies {
            $0.logClient.info = { _, _ in }
            $0.logClient.debug = { _, _ in }
            $0.logClient.error = { _, _ in }
            $0.audioClient.unfinishedRecordings = { [audio] }
            $0.transcriptionClient.transcribe = { _, _, _ in
                if decoderFails { throw CocoaError(.fileReadCorruptFile) }
                return ""
            }
            $0.pasteClient.copy = { text in copies.withValue { $0.append(text) } }
            $0.historyClient.persistArtifacts = { _ in nil }
        } operation: {
            let model = makeModel()
            await model.recoverUnfinishedRecordings()
            return model.menuTransientMessage
        }

        #expect(message == (decoderFails ? "Transcription failed" : nil))
        #expect(copies.value.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: audio.path))
    }

    private func makeModel(with entry: TranscriptHistoryEntry? = nil) -> AppModel {
        let model = AppModel()
        model.$hasCompletedSetup.withLock { $0 = true }
        model.$historyRetentionMode.withLock { $0 = .both }
        if let entry {
            model.$transcriptHistoryDays.withLock { $0 = [TranscriptHistoryDay(day: "1970-01-02", entries: [entry])] }
        }
        return model
    }

    private func historyEntry() -> TranscriptHistoryEntry {
        TranscriptHistoryEntry(
            id: UUID(), timestamp: Date(timeIntervalSince1970: 86_400), modelID: ModelOption.defaultOption.rawValue,
            audioDurationSeconds: 10, audioRelativePath: "media/previous.m4a",
            variants: [TranscriptHistoryVariant(
                mode: "verbatim", transcriptionElapsedSeconds: 1, characterCount: 5,
                pasteResult: "pasted", transcriptRelativePath: "transcripts/previous.txt"
            )]
        )
    }
}
