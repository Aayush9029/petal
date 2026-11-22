import Foundation
import Shared

nonisolated struct LoadedHistoryEntry: Equatable, Sendable {
    let entry: TranscriptHistoryEntry
    let contents: HistoryEntryContents
    let searchText: String

    init(day: String, entry: TranscriptHistoryEntry, contents: HistoryEntryContents) {
        self.entry = entry
        self.contents = contents
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
