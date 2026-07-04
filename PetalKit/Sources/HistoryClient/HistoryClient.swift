import AppKit
@preconcurrency import AVFoundation
import Dependencies
import DependenciesMacros
import Foundation
import Shared

@DependencyClient
public struct HistoryClient: Sendable {
    public var bootstrap: @Sendable (HistoryRetentionMode, [TranscriptHistoryDay]) -> [TranscriptHistoryDay] = { _, days in days }
    public var applyRetention: @Sendable (HistoryRetentionMode, [TranscriptHistoryDay]) -> [TranscriptHistoryDay] = { _, days in days }
    public var appendEntry: @Sendable (AppendEntryRequest) -> [TranscriptHistoryDay] = { _ in [] }
    public var persistArtifacts: @Sendable (PersistArtifactsRequest) async -> PersistedArtifacts? = { _ in nil }
    public var cleanHistoryOlderThan: @Sendable (Int, HistoryRetentionMode, [TranscriptHistoryDay]) -> [TranscriptHistoryDay] = { _, _, days in days }
    public var openHistoryFolder: @Sendable (HistoryRetentionMode) -> Bool = { _ in false }
    public var historyAudioURL: @Sendable (String?) -> URL? = { _ in nil }
    public var transcriptText: @Sendable (String?) -> String? = { _ in nil }
    public var modelsDirectoryPath: @Sendable () -> String = { "" }
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
        sessionID: UUID
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
            bootstrap: { retentionMode, storedDays in
                runtime.applyRetention(retentionMode, to: storedDays)
            },
            applyRetention: { retentionMode, currentDays in
                runtime.applyRetention(retentionMode, to: currentDays)
            },
            appendEntry: { request in
                runtime.appendEntry(request)
            },
            persistArtifacts: { request in
                await runtime.persistArtifacts(request)
            },
            cleanHistoryOlderThan: { daysToKeep, retentionMode, days in
                runtime.cleanHistoryOlderThan(daysToKeep: daysToKeep, retentionMode: retentionMode, days: days)
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
            modelsDirectoryPath: {
                runtime.modelsDirectoryPath
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

private final class HistoryRuntime: @unchecked Sendable {
    var modelsDirectoryPath: String { Self.modelsDirectoryURL.path }
    var historyDirectoryPath: String { Self.historyDirectoryURL.path }

    func applyRetention(
        _ retentionMode: HistoryRetentionMode,
        to currentDays: [TranscriptHistoryDay]
    ) -> [TranscriptHistoryDay] {
        if !retentionMode.keepsHistory {
            clearPersistedHistoryArtifacts()
            return []
        }
        ensureDataDirectories(retentionMode: retentionMode)
        let retained = pruned(days: currentDays, retentionMode: retentionMode)
        return healed(days: retained, retentionMode: retentionMode)
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
        if let dayIndex = updatedDays.firstIndex(where: { $0.day == day }) {
            if var existingEntry = updatedDays[dayIndex].entries[id: request.sessionID] {
                existingEntry.timestamp = request.timestamp
                existingEntry.modelID = request.modelID
                existingEntry.audioDurationSeconds = request.audioDuration
                if let audioRelativePath = request.audioRelativePath {
                    existingEntry.audioRelativePath = audioRelativePath
                }
                existingEntry.variants[id: variant.id] = variant
                updatedDays[dayIndex].entries[id: existingEntry.id] = existingEntry
            } else {
                let entry = TranscriptHistoryEntry(
                    id: request.sessionID,
                    timestamp: request.timestamp,
                    modelID: request.modelID,
                    audioDurationSeconds: request.audioDuration,
                    audioRelativePath: request.audioRelativePath,
                    variants: [variant]
                )
                updatedDays[dayIndex].entries.insert(entry, at: 0)
            }
            updatedDays[dayIndex].entries = Self.sortedAndCapped(updatedDays[dayIndex].entries)
        } else {
            let entry = TranscriptHistoryEntry(
                id: request.sessionID,
                timestamp: request.timestamp,
                modelID: request.modelID,
                audioDurationSeconds: request.audioDuration,
                audioRelativePath: request.audioRelativePath,
                variants: [variant]
            )
            updatedDays.append(TranscriptHistoryDay(day: day, entries: [entry]))
        }
        updatedDays.sort { $0.day > $1.day }
        return updatedDays
    }

    func persistArtifacts(_ request: PersistArtifactsRequest) async -> PersistedArtifacts? {
        guard request.retentionMode.keepsHistory else { return nil }
        ensureDataDirectories(retentionMode: request.retentionMode)

        let fileManager = FileManager.default
        let stamp = Self.historyArtifactFormatter.string(from: request.timestamp)
        let safeModelID = request.modelID.replacingOccurrences(of: "/", with: "-")
        let safeMode = request.mode.replacingOccurrences(of: "/", with: "-")
        let baseName = "\(stamp)-\(safeModelID)"

        let audioTarget = Self.historyMediaDirectoryURL.appending(path: "\(baseName).m4a")
        let transcriptTarget = Self.historyTranscriptsDirectoryURL.appending(path: "\(baseName)-\(safeMode).txt")

        var artifacts = PersistedArtifacts()
        do {
            if request.retentionMode.keepsAudio && request.persistAudio {
                if fileManager.fileExists(atPath: audioTarget.path) {
                    try fileManager.removeItem(at: audioTarget)
                }
                let audioCompressionProfile: HistoryAudioCompressionProfile = request.compressAudio ? .aggressive : .standard
                try await Self.encodeHistoryAudio(from: request.audioURL, to: audioTarget, profile: audioCompressionProfile)
                Self.applyProtection(to: audioTarget)
                artifacts.audioRelativePath = "media/\(audioTarget.lastPathComponent)"
            }
            if request.retentionMode.keepsTranscripts {
                if fileManager.fileExists(atPath: transcriptTarget.path) {
                    try fileManager.removeItem(at: transcriptTarget)
                }
                try request.transcript.write(to: transcriptTarget, atomically: true, encoding: .utf8)
                Self.applyProtection(to: transcriptTarget)
                artifacts.transcriptRelativePath = "transcripts/\(transcriptTarget.lastPathComponent)"
            }
            return artifacts
        } catch {
            return nil
        }
    }

    func cleanHistoryOlderThan(daysToKeep: Int, retentionMode: HistoryRetentionMode, days: [TranscriptHistoryDay]) -> [TranscriptHistoryDay] {
        guard daysToKeep > 0 else { return days }

        let cutoff = Date().addingTimeInterval(-Double(daysToKeep) * 24 * 60 * 60)
        var pathsToDelete = Set<String>()
        var updatedDays: [TranscriptHistoryDay] = []

        for day in days {
            let keptEntries = day.entries.filter { entry in
                let keep = entry.timestamp >= cutoff
                if !keep {
                    if let audioPath = entry.audioRelativePath {
                        pathsToDelete.insert(audioPath)
                    }
                    for variant in entry.variants {
                        if let transcriptPath = variant.transcriptRelativePath {
                            pathsToDelete.insert(transcriptPath)
                        }
                    }
                }
                return keep
            }

            if !keptEntries.isEmpty {
                updatedDays.append(
                    TranscriptHistoryDay(
                        day: day.day,
                        entries: IdentifiedArray(uniqueElements: keptEntries)
                    )
                )
            }
        }

        for path in pathsToDelete {
            removeHistoryFile(relativePath: path)
        }

        let retained = pruned(days: updatedDays, retentionMode: retentionMode)
        return healed(days: retained, retentionMode: retentionMode)
    }

    func openHistoryFolder(retentionMode: HistoryRetentionMode) -> Bool {
        guard retentionMode.keepsHistory else { return false }
        if !FileManager.default.fileExists(atPath: Self.historyDirectoryURL.path) {
            ensureDataDirectories(retentionMode: retentionMode)
        }
        NSWorkspace.shared.open(Self.historyDirectoryURL)
        return true
    }

    func historyAudioURL(relativePath: String?) -> URL? {
        guard let relativePath else { return nil }
        guard let audioURL = historyURL(relativePath: relativePath) else { return nil }
        guard FileManager.default.fileExists(atPath: audioURL.path) else { return nil }
        return audioURL
    }

    func transcriptText(relativePath: String?) -> String? {
        guard let relativePath else { return nil }
        guard let transcriptURL = historyURL(relativePath: relativePath) else { return nil }
        guard FileManager.default.fileExists(atPath: transcriptURL.path) else { return nil }
        return try? String(contentsOf: transcriptURL, encoding: .utf8)
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
        var pathsToDelete = Set<String>()
        var updatedDays: [TranscriptHistoryDay] = []

        for day in days {
            let keptEntries = day.entries.filter { entry in
                guard entry.id == entryID else { return true }
                if let audioPath = entry.audioRelativePath {
                    pathsToDelete.insert(audioPath)
                }
                for variant in entry.variants {
                    if let transcriptPath = variant.transcriptRelativePath {
                        pathsToDelete.insert(transcriptPath)
                    }
                }
                return false
            }

            if !keptEntries.isEmpty {
                updatedDays.append(
                    TranscriptHistoryDay(
                        day: day.day,
                        entries: IdentifiedArray(uniqueElements: keptEntries)
                    )
                )
            }
        }

        for path in pathsToDelete {
            removeHistoryFile(relativePath: path)
        }

        updatedDays.sort { $0.day > $1.day }
        return updatedDays
    }

    private func ensureDataDirectories(retentionMode: HistoryRetentionMode) {
        let fileManager = FileManager.default
        Self.ensureDirectory(Self.modelsDirectoryURL, using: fileManager)
        Self.ensureDirectory(Self.historyDirectoryURL, using: fileManager)
        if retentionMode.keepsAudio {
            Self.ensureDirectory(Self.historyMediaDirectoryURL, using: fileManager)
        } else {
            try? fileManager.removeItem(at: Self.historyMediaDirectoryURL)
        }
        if retentionMode.keepsTranscripts {
            Self.ensureDirectory(Self.historyTranscriptsDirectoryURL, using: fileManager)
        } else {
            try? fileManager.removeItem(at: Self.historyTranscriptsDirectoryURL)
        }
    }

    private func clearPersistedHistoryArtifacts() {
        try? FileManager.default.removeItem(at: Self.historyDirectoryURL)
    }

    private func pruned(
        days: [TranscriptHistoryDay],
        retentionMode: HistoryRetentionMode
    ) -> [TranscriptHistoryDay] {
        var updatedDays = days
        if !retentionMode.keepsAudio {
            for dayIndex in updatedDays.indices {
                for entryID in updatedDays[dayIndex].entries.ids {
                    updatedDays[dayIndex].entries[id: entryID]?.audioRelativePath = nil
                }
            }
        }
        if !retentionMode.keepsTranscripts {
            for dayIndex in updatedDays.indices {
                for entryID in updatedDays[dayIndex].entries.ids {
                    guard var entry = updatedDays[dayIndex].entries[id: entryID] else { continue }
                    for variantID in entry.variants.ids {
                        entry.variants[id: variantID]?.transcriptRelativePath = nil
                    }
                    updatedDays[dayIndex].entries[id: entryID] = entry
                }
            }
        }
        return updatedDays
    }

    private func healed(
        days: [TranscriptHistoryDay],
        retentionMode: HistoryRetentionMode
    ) -> [TranscriptHistoryDay] {
        var healedDays: [TranscriptHistoryDay] = []

        for day in days {
            var healedEntries: [TranscriptHistoryEntry] = []

            for entry in day.entries {
                var healedEntry = entry

                if retentionMode.keepsAudio,
                   let audioRelativePath = healedEntry.audioRelativePath,
                   historyURL(relativePath: audioRelativePath).map({ FileManager.default.fileExists(atPath: $0.path) }) != true
                {
                    healedEntry.audioRelativePath = nil
                }

                if retentionMode.keepsTranscripts {
                    healedEntry.variants = IdentifiedArray(
                        uniqueElements: healedEntry.variants.compactMap { variant in
                            guard let transcriptRelativePath = variant.transcriptRelativePath else { return nil }
                            guard let transcriptURL = historyURL(relativePath: transcriptRelativePath),
                                  FileManager.default.fileExists(atPath: transcriptURL.path)
                            else {
                                return nil
                            }
                            return variant
                        }
                    )
                }

                if !healedEntry.variants.isEmpty {
                    healedEntries.append(healedEntry)
                }
            }

            if !healedEntries.isEmpty {
                healedDays.append(
                    TranscriptHistoryDay(
                        day: day.day,
                        entries: IdentifiedArray(uniqueElements: healedEntries.sorted { $0.timestamp > $1.timestamp })
                    )
                )
            }
        }

        healedDays.sort { $0.day > $1.day }
        return healedDays
    }

    private func historyURL(relativePath: String) -> URL? {
        let candidate = Self.historyDirectoryURL.appending(path: relativePath).standardizedFileURL
        let base = Self.historyDirectoryURL.standardizedFileURL
        guard candidate.path.hasPrefix(base.path + "/") else { return nil }
        return candidate
    }

    private func removeHistoryFile(relativePath: String) {
        guard let fileURL = historyURL(relativePath: relativePath) else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static func sortedAndCapped(_ entries: IdentifiedArrayOf<TranscriptHistoryEntry>) -> IdentifiedArrayOf<TranscriptHistoryEntry> {
        var sorted = IdentifiedArray(uniqueElements: entries.sorted { $0.timestamp > $1.timestamp })
        if sorted.count > 200 {
            sorted.removeLast(sorted.count - 200)
        }
        return sorted
    }

    private static let historyDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let historyArtifactFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

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

    private static var appDocumentsDirectoryURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appending(path: "petal", directoryHint: .isDirectory)
    }

    private static var modelsDirectoryURL: URL {
        appDocumentsDirectoryURL.appending(path: "models", directoryHint: .isDirectory)
    }

    private static var historyDirectoryURL: URL {
        appDocumentsDirectoryURL.appending(path: "history", directoryHint: .isDirectory)
    }

    private static var historyMediaDirectoryURL: URL {
        historyDirectoryURL.appending(path: "media", directoryHint: .isDirectory)
    }

    private static var historyTranscriptsDirectoryURL: URL {
        historyDirectoryURL.appending(path: "transcripts", directoryHint: .isDirectory)
    }

    private enum HistoryAudioCompressionProfile: Sendable {
        case standard
        case aggressive

        var sampleRate: Double {
            switch self {
            case .standard:
                return 22_050
            case .aggressive:
                return 16_000
            }
        }

        var bitRate: Int {
            switch self {
            case .standard:
                return 64_000
            case .aggressive:
                return 24_000
            }
        }
    }

    private static func encodeHistoryAudio(
        from source: URL,
        to destination: URL,
        profile: HistoryAudioCompressionProfile
    ) async throws {
        try await Task.detached(priority: .utility) {
            try await transcodeHistoryAudio(from: source, to: destination, profile: profile)
        }.value
    }

    private static func transcodeHistoryAudio(
        from source: URL,
        to destination: URL,
        profile: HistoryAudioCompressionProfile
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
                AVSampleRateKey: profile.sampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: profile.bitRate
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
