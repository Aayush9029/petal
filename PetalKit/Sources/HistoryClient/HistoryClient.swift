import AppKit
import Dependencies
import DependenciesMacros
import Foundation
import OSLog
import Shared

@DependencyClient
public struct HistoryClient: Sendable {
    public var applyRetention: @Sendable (HistoryRetentionMode, [TranscriptHistoryDay]) -> [TranscriptHistoryDay] = { _, days in days }
    public var appendEntry: @Sendable (AppendEntryRequest) -> [TranscriptHistoryDay] = { _ in [] }
    public var discardArtifacts: @Sendable (PersistedArtifacts) -> Void = { _ in }
    public var persistArtifacts: @Sendable (PersistArtifactsRequest) async -> PersistedArtifacts? = { _ in nil }
    public var openHistoryFolder: @Sendable (HistoryRetentionMode) -> Bool = { _ in false }
    public var historyAudioURL: @Sendable (String?) -> URL? = { _ in nil }
    public var transcriptText: @Sendable (String?) -> String? = { _ in nil }
    public var entryContents: @Sendable ([TranscriptHistoryEntry]) async -> [UUID: HistoryEntryContents] = { _ in [:] }
    public var historyDirectoryPath: @Sendable () -> String = { "" }
    public var deleteEntry: @Sendable ([TranscriptHistoryDay], UUID) -> [TranscriptHistoryDay] = { days, _ in days }
    public var deleteMediaOnly: @Sendable ([TranscriptHistoryDay]) -> [TranscriptHistoryDay] = { days in days }
}

public struct AppendEntryRequest: Sendable {
    public var currentDays: [TranscriptHistoryDay]
    public var transcript: String
    public var modelID: String
    public var mode: String
    public var audioDuration: Double
    public var transcriptionElapsed: Double
    public var pasteResult: String
    public var audioRelativePath: String?
    public var transcriptRelativePath: String?
    public var retentionMode: HistoryRetentionMode
    public var timestamp: Date
    public var sessionID: UUID
    public var app: FocusedApp?
    public var replacesVariants: Bool

    public init(
        currentDays: [TranscriptHistoryDay],
        transcript: String,
        modelID: String,
        mode: String,
        audioDuration: Double,
        transcriptionElapsed: Double,
        pasteResult: String,
        audioRelativePath: String?,
        transcriptRelativePath: String?,
        retentionMode: HistoryRetentionMode,
        timestamp: Date,
        sessionID: UUID,
        app: FocusedApp? = nil,
        replacesVariants: Bool = false
    ) {
        self.currentDays = currentDays
        self.transcript = transcript
        self.modelID = modelID
        self.mode = mode
        self.audioDuration = audioDuration
        self.transcriptionElapsed = transcriptionElapsed
        self.pasteResult = pasteResult
        self.audioRelativePath = audioRelativePath
        self.transcriptRelativePath = transcriptRelativePath
        self.retentionMode = retentionMode
        self.timestamp = timestamp
        self.sessionID = sessionID
        self.app = app
        self.replacesVariants = replacesVariants
    }
}

public struct PersistArtifactsRequest: Sendable {
    public var audioURL: URL
    public var transcript: String
    public var timestamp: Date
    public var mode: String
    public var modelID: String
    public var retentionMode: HistoryRetentionMode
    public var compressAudio: Bool
    public var persistAudio: Bool

    public init(
        audioURL: URL,
        transcript: String,
        timestamp: Date,
        mode: String,
        modelID: String,
        retentionMode: HistoryRetentionMode,
        compressAudio: Bool = false,
        persistAudio: Bool = true
    ) {
        self.audioURL = audioURL
        self.transcript = transcript
        self.timestamp = timestamp
        self.mode = mode
        self.modelID = modelID
        self.retentionMode = retentionMode
        self.compressAudio = compressAudio
        self.persistAudio = persistAudio
    }
}

public struct PersistedArtifacts: Sendable {
    public var audioRelativePath: String?
    public var transcriptRelativePath: String?

    public init(audioRelativePath: String? = nil, transcriptRelativePath: String? = nil) {
        self.audioRelativePath = audioRelativePath
        self.transcriptRelativePath = transcriptRelativePath
    }
}

extension HistoryClient: DependencyKey {
    public static var liveValue: Self {
        let runtime = HistoryRuntime()
        return Self(
            applyRetention: { retentionMode, currentDays in
                runtime.applyRetention(retentionMode, to: currentDays)
            },
            appendEntry: { request in
                runtime.appendEntry(request)
            },
            discardArtifacts: { artifacts in runtime.discardArtifacts(artifacts) },
            persistArtifacts: { request in
                await runtime.persistArtifacts(request)
            },
            openHistoryFolder: { retentionMode in
                runtime.openHistoryFolder(retentionMode: retentionMode)
            },
            historyAudioURL: { relativePath in
                runtime.historyAudioURL(relativePath: relativePath)
            },
            transcriptText: { relativePath in
                runtime.transcriptText(relativePath: relativePath)
            },
            entryContents: { entries in
                await runtime.entryContents(entries)
            },
            historyDirectoryPath: {
                runtime.historyDirectoryPath
            },
            deleteEntry: { days, entryID in
                runtime.deleteEntry(id: entryID, from: days)
            },
            deleteMediaOnly: { days in
                runtime.deleteMediaOnly(days: days)
            }
        )
    }
}

extension HistoryClient: TestDependencyKey {
    public static var testValue: Self {
        Self()
    }
}

public extension DependencyValues {
    var historyClient: HistoryClient {
        get { self[HistoryClient.self] }
        set { self[HistoryClient.self] = newValue }
    }
}

private struct HistoryRuntime: Sendable {
    var historyDirectoryPath: String { PetalPaths.history.path }

    func applyRetention(
        _ retentionMode: HistoryRetentionMode,
        to currentDays: [TranscriptHistoryDay]
    ) -> [TranscriptHistoryDay] {
        if !retentionMode.keepsHistory {
            try? FileManager.default.removeItem(at: PetalPaths.history)
            return []
        }
        if !retentionMode.keepsAudio {
            try? FileManager.default.removeItem(at: Self.historyMediaDirectoryURL)
        }
        if !retentionMode.keepsTranscripts {
            try? FileManager.default.removeItem(at: Self.historyTranscriptsDirectoryURL)
        }
        ensureDataDirectories(retentionMode: retentionMode)
        return reconciled(currentDays, retentionMode: retentionMode)
    }

    func appendEntry(_ request: AppendEntryRequest) -> [TranscriptHistoryDay] {
        guard request.retentionMode.keepsHistory else { return request.currentDays }

        let variant = TranscriptHistoryVariant(
            mode: request.mode,
            transcriptionElapsedSeconds: request.transcriptionElapsed,
            characterCount: request.transcript.count,
            pasteResult: request.pasteResult,
            transcriptRelativePath: request.transcriptRelativePath
        )
        let day = Self.historyDayFormatter.string(from: request.timestamp)

        var updatedDays = request.currentDays
        let dayIndex = updatedDays.firstIndex { $0.day == day } ?? updatedDays.endIndex
        if dayIndex == updatedDays.endIndex {
            updatedDays.append(TranscriptHistoryDay(day: day))
        }
        let existing = updatedDays[dayIndex].entries[id: request.sessionID]
        var variants = request.replacesVariants ? [] : existing?.variants ?? []
        variants[id: variant.id] = variant
        let entry = TranscriptHistoryEntry(
            id: request.sessionID,
            timestamp: request.timestamp,
            modelID: request.modelID,
            audioDurationSeconds: request.audioDuration,
            audioRelativePath: request.audioRelativePath ?? existing?.audioRelativePath,
            app: request.app ?? existing?.app,
            variants: variants
        )
        updatedDays[dayIndex].entries[id: entry.id] = entry
        updatedDays[dayIndex].entries.sort { $0.timestamp > $1.timestamp }
        updatedDays.sort { $0.day > $1.day }
        if let existing {
            removeUnusedArtifacts(existing.artifactPaths.subtracting(entry.artifactPaths), from: updatedDays)
        }
        return updatedDays
    }

    func persistArtifacts(_ request: PersistArtifactsRequest) async -> PersistedArtifacts? {
        guard request.retentionMode.keepsHistory else { return nil }
        ensureDataDirectories(retentionMode: request.retentionMode)

        let stamp = Self.historyArtifactFormatter.string(from: request.timestamp)
        let safeModelID = request.modelID.replacingOccurrences(of: "/", with: "-")
        let safeMode = request.mode.replacingOccurrences(of: "/", with: "-")
        let baseName = "\(stamp)-\(safeModelID)-\(UUID().uuidString)"

        let audioTarget = Self.historyMediaDirectoryURL.appending(path: "\(baseName).m4a")
        let transcriptTarget = Self.historyTranscriptsDirectoryURL.appending(path: "\(baseName)-\(safeMode).txt")

        var artifacts = PersistedArtifacts()
        do {
            if request.retentionMode.keepsAudio && request.persistAudio {
                let audioCompressionProfile: HistoryAudioCompressionProfile = request.compressAudio ? .aggressive : .standard
                try await audioCompressionProfile.encode(from: request.audioURL, to: audioTarget)
                Self.applyProtection(to: audioTarget)
                artifacts.audioRelativePath = "media/\(audioTarget.lastPathComponent)"
            }
            if request.retentionMode.keepsTranscripts {
                try request.transcript.write(to: transcriptTarget, atomically: true, encoding: .utf8)
                Self.applyProtection(to: transcriptTarget)
                artifacts.transcriptRelativePath = "transcripts/\(transcriptTarget.lastPathComponent)"
            }
            return artifacts
        } catch {
            try? FileManager.default.removeItem(at: audioTarget)
            try? FileManager.default.removeItem(at: transcriptTarget)
            Logger(subsystem: "com.optimalapps.petal", category: "HistoryClient")
                .error("Could not save history artifacts: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func discardArtifacts(_ artifacts: PersistedArtifacts) {
        for path in [artifacts.audioRelativePath, artifacts.transcriptRelativePath].compactMap({ $0 }) {
            guard let url = historyURL(relativePath: path) else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    func openHistoryFolder(retentionMode: HistoryRetentionMode) -> Bool {
        guard retentionMode.keepsHistory else { return false }
        if !FileManager.default.fileExists(atPath: PetalPaths.history.path) {
            ensureDataDirectories(retentionMode: retentionMode)
        }
        NSWorkspace.shared.open(PetalPaths.history)
        return true
    }

    func historyAudioURL(relativePath: String?) -> URL? {
        existingArtifact(at: relativePath)
    }

    func transcriptText(relativePath: String?) -> String? {
        guard let transcriptURL = existingArtifact(at: relativePath) else { return nil }
        return try? String(contentsOf: transcriptURL, encoding: .utf8)
    }

    func entryContents(_ entries: [TranscriptHistoryEntry]) async -> [UUID: HistoryEntryContents] {
        let chunkSize = 64
        return await withTaskGroup(of: [(UUID, HistoryEntryContents)].self) { group in
            for start in stride(from: 0, to: entries.count, by: chunkSize) {
                let chunk = entries[start ..< min(start + chunkSize, entries.count)]
                group.addTask {
                    chunk.map { ($0.id, self.contents(of: $0)) }
                }
            }
            var contents: [UUID: HistoryEntryContents] = [:]
            contents.reserveCapacity(entries.count)
            for await pairs in group {
                for (id, entryContents) in pairs {
                    contents[id] = entryContents
                }
            }
            return contents
        }
    }

    private func contents(of entry: TranscriptHistoryEntry) -> HistoryEntryContents {
        HistoryEntryContents(
            transcript: transcriptText(relativePath: entry.transcriptVariant?.transcriptRelativePath) ?? "",
            cleanup: entry.cleanupVariant.flatMap { transcriptText(relativePath: $0.transcriptRelativePath) },
            audioURL: historyAudioURL(relativePath: entry.audioRelativePath)
        )
    }

    func deleteMediaOnly(days: [TranscriptHistoryDay]) -> [TranscriptHistoryDay] {
        try? FileManager.default.removeItem(at: Self.historyMediaDirectoryURL)
        var updatedDays = days
        for dayIndex in updatedDays.indices {
            for entryID in updatedDays[dayIndex].entries.ids {
                updatedDays[dayIndex].entries[id: entryID]?.audioRelativePath = nil
            }
        }
        return updatedDays
    }

    func deleteEntry(id entryID: UUID, from days: [TranscriptHistoryDay]) -> [TranscriptHistoryDay] {
        var removedPaths = Set<String>()
        let updatedDays = days.compactMap { day -> TranscriptHistoryDay? in
            var day = day
            if let removed = day.entries.remove(id: entryID) {
                removedPaths.formUnion(removed.artifactPaths)
            }
            return day.entries.isEmpty ? nil : day
        }
        removeUnusedArtifacts(removedPaths, from: updatedDays)
        return updatedDays.sorted { $0.day > $1.day }
    }

    private func removeUnusedArtifacts(_ paths: Set<String>, from remainingDays: [TranscriptHistoryDay]) {
        guard !paths.isEmpty else { return }
        var unused = paths
        for day in remainingDays {
            for entry in day.entries {
                unused.subtract(entry.artifactPaths)
            }
        }
        for path in unused {
            guard let url = historyURL(relativePath: path) else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func ensureDataDirectories(retentionMode: HistoryRetentionMode) {
        let fileManager = FileManager.default
        Self.ensureDirectory(PetalPaths.history, using: fileManager)
        if retentionMode.keepsAudio {
            Self.ensureDirectory(Self.historyMediaDirectoryURL, using: fileManager)
        }
        if retentionMode.keepsTranscripts {
            Self.ensureDirectory(Self.historyTranscriptsDirectoryURL, using: fileManager)
        }
    }

    private func reconciled(
        _ days: [TranscriptHistoryDay],
        retentionMode: HistoryRetentionMode
    ) -> [TranscriptHistoryDay] {
        days.compactMap { day in
            let entries = day.entries.compactMap { entry -> TranscriptHistoryEntry? in
                var entry = entry
                if !retentionMode.keepsAudio || existingArtifact(at: entry.audioRelativePath) == nil {
                    entry.audioRelativePath = nil
                }
                entry.variants = IdentifiedArray(uniqueElements: entry.variants.compactMap { variant in
                    if retentionMode.keepsTranscripts, existingArtifact(at: variant.transcriptRelativePath) != nil {
                        return variant
                    }
                    guard !retentionMode.keepsTranscripts || entry.audioRelativePath != nil else { return nil }
                    var variant = variant
                    variant.transcriptRelativePath = nil
                    return variant
                })
                return entry.variants.isEmpty ? nil : entry
            }
            guard !entries.isEmpty else { return nil }
            return TranscriptHistoryDay(day: day.day, entries: IdentifiedArray(uniqueElements: entries.sorted { $0.timestamp > $1.timestamp }))
        }
        .sorted { $0.day > $1.day }
    }

    private func existingArtifact(at relativePath: String?) -> URL? {
        guard let relativePath, let url = historyURL(relativePath: relativePath),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    private func historyURL(relativePath: String) -> URL? {
        let candidate = PetalPaths.history.appending(path: relativePath).standardizedFileURL
        let base = PetalPaths.history.standardizedFileURL
        guard candidate.path.hasPrefix(base.path + "/") else { return nil }
        return candidate
    }

    private static let historyDayFormatter = formatter("yyyy-MM-dd")
    private static let historyArtifactFormatter = formatter("yyyyMMdd-HHmmss")

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = format
        return formatter
    }

    private static var protectedAttributes: [FileAttributeKey: Any] {
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
    }

    private static func ensureDirectory(_ url: URL, using fileManager: FileManager) {
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: protectedAttributes)
        applyProtection(to: url, using: fileManager)
    }

    private static func applyProtection(to url: URL, using fileManager: FileManager = FileManager.default) {
        try? fileManager.setAttributes(protectedAttributes, ofItemAtPath: url.path)
    }

    private static var historyMediaDirectoryURL: URL {
        PetalPaths.history.appending(path: "media", directoryHint: .isDirectory)
    }

    private static var historyTranscriptsDirectoryURL: URL {
        PetalPaths.history.appending(path: "transcripts", directoryHint: .isDirectory)
    }
}

private extension TranscriptHistoryEntry {
    var artifactPaths: Set<String> {
        var paths = Set(variants.compactMap(\.transcriptRelativePath))
        if let audioRelativePath { paths.insert(audioRelativePath) }
        return paths
    }
}
