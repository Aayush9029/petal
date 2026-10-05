import Foundation
import Shared
import Testing
@testable import HistoryClient

@Suite("History entry contents", .serialized)
struct HistoryEntryContentsTests {
    @Test
    func readsTranscriptCleanupAndAudioForEachEntry() async throws {
        let historyClient = HistoryClient.liveValue
        _ = historyClient.applyRetention(.both, [])
        let prefix = UUID().uuidString
        let original = try writeHistoryFile("transcripts/\(prefix)-original.txt", contents: "um so the plan is ready")
        let cleaned = try writeHistoryFile("transcripts/\(prefix)-smart.txt", contents: "The plan is ready.")
        let audio = try writeHistoryFile("media/\(prefix).m4a", contents: "audio")
        let plain = try writeHistoryFile("transcripts/\(prefix)-verbatim.txt", contents: "Hello there")
        defer {
            for path in [original, cleaned, audio, plain] {
                try? FileManager.default.removeItem(at: path)
            }
        }

        let cleanedEntry = TranscriptHistoryEntry(
            id: UUID(),
            timestamp: Date(),
            modelID: "test-model",
            audioDurationSeconds: 2,
            audioRelativePath: "media/\(prefix).m4a",
            variants: [
                TranscriptHistoryVariant(mode: TranscriptHistoryVariant.originalMode, transcriptionElapsedSeconds: 1, characterCount: 23, pasteResult: "skipped", transcriptRelativePath: "transcripts/\(prefix)-original.txt"),
                TranscriptHistoryVariant(mode: "smart", transcriptionElapsedSeconds: 1, characterCount: 18, pasteResult: "pasted", transcriptRelativePath: "transcripts/\(prefix)-smart.txt"),
            ]
        )
        let plainEntry = TranscriptHistoryEntry(
            id: UUID(),
            timestamp: Date(),
            modelID: "test-model",
            audioDurationSeconds: 1,
            audioRelativePath: "media/\(prefix)-missing.m4a",
            variants: [
                TranscriptHistoryVariant(mode: "verbatim", transcriptionElapsedSeconds: 1, characterCount: 11, pasteResult: "pasted", transcriptRelativePath: "transcripts/\(prefix)-verbatim.txt"),
            ]
        )
        let missingEntry = TranscriptHistoryEntry(
            id: UUID(),
            timestamp: Date(),
            modelID: "test-model",
            audioDurationSeconds: 1,
            audioRelativePath: "../outside.m4a",
            variants: [
                TranscriptHistoryVariant(mode: "verbatim", transcriptionElapsedSeconds: 1, characterCount: 0, pasteResult: "skipped", transcriptRelativePath: "transcripts/\(prefix)-gone.txt"),
            ]
        )

        let contents = await historyClient.entryContents([cleanedEntry, plainEntry, missingEntry])

        #expect(contents.count == 3)
        #expect(contents[cleanedEntry.id] == HistoryEntryContents(
            transcript: "um so the plan is ready",
            cleanup: "The plan is ready.",
            audioURL: historyClient.historyAudioURL("media/\(prefix).m4a")
        ))
        #expect(contents[cleanedEntry.id]?.audioURL != nil)
        #expect(contents[plainEntry.id] == HistoryEntryContents(transcript: "Hello there"))
        #expect(contents[missingEntry.id] == HistoryEntryContents())
    }

    @Test
    func loadsEveryEntryAcrossBatches() async throws {
        let historyClient = HistoryClient.liveValue
        _ = historyClient.applyRetention(.both, [])
        let prefix = UUID().uuidString
        var files: [URL] = []
        defer {
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
        }

        var entries: [TranscriptHistoryEntry] = []
        for index in 0 ..< 150 {
            let path = "transcripts/\(prefix)-\(index).txt"
            files.append(try writeHistoryFile(path, contents: "Transcript \(index)"))
            entries.append(
                TranscriptHistoryEntry(
                    id: UUID(),
                    timestamp: Date(),
                    modelID: "test-model",
                    audioDurationSeconds: 1,
                    variants: [
                        TranscriptHistoryVariant(mode: "verbatim", transcriptionElapsedSeconds: 1, characterCount: 12, pasteResult: "pasted", transcriptRelativePath: path),
                    ]
                )
            )
        }

        let contents = await historyClient.entryContents(entries)

        #expect(contents.count == entries.count)
        for (index, entry) in entries.enumerated() {
            #expect(contents[entry.id]?.transcript == "Transcript \(index)")
        }
    }
}

private func writeHistoryFile(_ relativePath: String, contents: String) throws -> URL {
    let url = URL(filePath: HistoryClient.liveValue.historyDirectoryPath()).appending(path: relativePath)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try contents.write(to: url, atomically: true, encoding: .utf8)
    return url
}
