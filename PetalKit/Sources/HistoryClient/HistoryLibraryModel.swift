import Combine
import Dependencies
import Foundation
import Observation
import Shared

@MainActor
@Observable
public final class HistoryLibraryModel {
    @ObservationIgnored @Dependency(\.historyClient) private var historyClient
    @ObservationIgnored @Shared(.historyRetentionMode) public var historyRetentionMode
    @ObservationIgnored @Shared(.transcriptHistoryDays) private var transcriptHistoryDays: [TranscriptHistoryDay]

    private var loadedHistory: [UUID: LoadedHistoryEntry] = [:]
    public private(set) var hasLoadedHistory = false
    private static let firstHistoryPageSize = 24

    public init() {}

    public var historyDirectoryDisplayPath: String {
        historyClient.historyDirectoryPath().replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~"
        )
    }

    private var historyDays: [TranscriptHistoryDay] {
        transcriptHistoryDays.sorted { $0.day > $1.day }
    }

    public func historyTask() async {
        // `Observations` needs macOS 26, so this follows the shared value through its publisher.
        for await _ in $transcriptHistoryDays.publisher.values {
            await loadHistory()
        }
    }

    public func historyDays(matching query: String) -> [TranscriptHistoryDay] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isShown = { (entry: TranscriptHistoryEntry) -> Bool in
            guard let loaded = self.loadedHistory[entry.id] else { return false }
            return search.isEmpty || loaded.searchText.contains(search)
        }
        return historyDays.compactMap { day in
            var filteredDay = day
            filteredDay.entries.removeAll { !isShown($0) }
            return filteredDay.entries.isEmpty ? nil : filteredDay
        }
    }

    public func contents(for entry: TranscriptHistoryEntry) -> HistoryEntryContents {
        loadedHistory[entry.id]?.contents ?? HistoryEntryContents()
    }

    public func historyRetentionModeChanged(_ mode: HistoryRetentionMode) {
        $historyRetentionMode.withLock { $0 = mode }
        let applied = historyClient.applyRetention(mode, transcriptHistoryDays)
        $transcriptHistoryDays.withLock { $0 = applied }
    }

    public func openHistoryInFinder() {
        _ = historyClient.openHistoryFolder(historyRetentionMode)
    }

    private func loadHistory() async {
        while !Task.isCancelled {
            var entryIDs = Set<UUID>()
            var stale: [(day: String, entry: TranscriptHistoryEntry)] = []
            for day in historyDays {
                for entry in day.entries {
                    entryIDs.insert(entry.id)
                    if loadedHistory[entry.id]?.entry != entry {
                        stale.append((day.day, entry))
                    }
                }
            }
            if loadedHistory.keys.contains(where: { !entryIDs.contains($0) }) {
                loadedHistory = loadedHistory.filter { entryIDs.contains($0.key) }
            }
            guard !stale.isEmpty else { break }

            let batch = hasLoadedHistory ? stale : Array(stale.prefix(Self.firstHistoryPageSize))
            let loaded = await Self.loadHistoryEntries(batch, historyClient: historyClient)
            guard !Task.isCancelled else { return }
            loadedHistory.merge(loaded) { $1 }
            hasLoadedHistory = true
        }
        if !Task.isCancelled {
            hasLoadedHistory = true
        }
    }

    @concurrent
    nonisolated private static func loadHistoryEntries(
        _ requests: [(day: String, entry: TranscriptHistoryEntry)],
        historyClient: HistoryClient
    ) async -> [UUID: LoadedHistoryEntry] {
        let contents = await historyClient.entryContents(requests.map { $0.entry })
        var loaded: [UUID: LoadedHistoryEntry] = [:]
        loaded.reserveCapacity(requests.count)
        for request in requests {
            loaded[request.entry.id] = LoadedHistoryEntry(
                day: request.day,
                entry: request.entry,
                contents: contents[request.entry.id] ?? HistoryEntryContents()
            )
        }
        return loaded
    }

    public func deleteAllHistory() {
        let cleared = historyClient.applyRetention(.none, transcriptHistoryDays)
        $transcriptHistoryDays.withLock { $0 = cleared }
    }

    public func deleteMediaOnly() {
        let updated = historyClient.deleteMediaOnly(transcriptHistoryDays)
        $transcriptHistoryDays.withLock { $0 = updated }
    }

}
