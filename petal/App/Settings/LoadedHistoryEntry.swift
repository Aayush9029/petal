import Foundation
import HistoryClient
import Shared

/// A recording's files, read once so History's view body never touches the disk.
nonisolated struct LoadedHistoryEntry: Equatable, Sendable {
    /// The version of the entry the files were read for. A changed entry loads again.
    let entry: TranscriptHistoryEntry
    let text: HistoryEntryText
    let audioURL: URL?
    /// Lowercased once here, so each keystroke in the search field only compares strings.
    let searchText: String

    init(day: String, entry: TranscriptHistoryEntry, contents: HistoryEntryContents) {
        self.entry = entry
        text = HistoryEntryText(transcript: contents.transcript, cleanup: contents.cleanup)
        audioURL = contents.audioURL
        searchText = [
            contents.transcript,
            contents.cleanup ?? "",
            entry.app?.app.name ?? "",
            entry.app?.website ?? "",
            entry.modelID,
            entry.modeSummary,
            day,
        ]
        .joined(separator: " ")
        .lowercased()
    }
}
