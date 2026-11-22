import AVFoundation
import Darwin
import Dependencies
import DownloadClient
import Foundation
import Sharing
import Shared
import Synchronization
import TranscriptionClient

public enum PetalCLI {
    public static func isInvocation(_ arguments: [String]) -> Bool {
        CLICommand.isInvocation(arguments)
    }

    /// Speech libraries print to stdout, so the transcript goes to a copy of the original stdout and fd 1 points at stderr.
    @MainActor
    public static func runAndExit(_ arguments: [String], version: String) -> Never {
        let output = dup(STDOUT_FILENO)
        dup2(STDERR_FILENO, STDOUT_FILENO)
        signal(SIGPIPE, SIG_IGN)

        let task = Task { await run(arguments, version: version, output: output) }
        let trap = SignalTrap(task: task)
        trap.install()
        Task { @MainActor in
            let code = await task.value
            trap.exit(code)
        }
        dispatchMain()
    }

    static func run(_ arguments: [String], version: String, output: Int32) async -> Int32 {
        do {
            switch try CLICommand.parse(arguments) {
            case .help:
                try write(CLIHelp.text + "\n", to: output)
            case .version:
                try write("petal \(version)\n", to: output)
            case let .models(json):
                try write(modelsReport(json: json), to: output)
            case let .transcribe(options):
                try await transcribe(options, output: output)
            }
            return 0
        } catch let error as CLIUsageError {
            printError("\(error.message)\nRun 'petal --help' for usage.")
            return 2
        } catch is CancellationError {
            return 130
        } catch let error as POSIXError where error.code == .EPIPE {
            return 0
        } catch {
            printError(error.localizedDescription)
            return 1
        }
    }

    // MARK: - Models

    static func modelsReport(json: Bool) throws -> String {
        @Dependency(\.downloadClient) var downloadClient
        let defaultModel = try? defaultModel()
        let rows = ModelOption.allCases.map { option in
            ModelRow(
                id: option.rawValue,
                name: option.displayName,
                provider: option.providerDisplayName,
                size: option.sizeLabel,
                downloaded: !option.requiresDownload || downloadClient.isModelDownloaded(option),
                isDefault: option == defaultModel
            )
        }

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            return String(decoding: try encoder.encode(rows), as: UTF8.self) + "\n"
        }

        let table = [["", "ID", "NAME", "SIZE", "STATUS"]] + rows.map { row in
            [
                row.isDefault ? "*" : "",
                row.id,
                row.name,
                row.size ?? "-",
                row.downloaded ? "ready" : "not downloaded",
            ]
        }
        let widths = (0 ..< 5).map { column in table.map { $0[column].count }.max() ?? 0 }
        let lines = table.map { cells in
            let line = zip(cells, widths)
                .map { $0.padding(toLength: $1, withPad: " ", startingAt: 0) }
                .joined(separator: "  ")
            return String(line.reversed().drop { $0 == " " }.reversed())
        }
        return lines.joined(separator: "\n") + "\n\n* The default model for 'petal transcribe'. Change it in Petal Settings.\n"
    }

    struct ModelRow: Encodable {
        var id: String
        var name: String
        var provider: String
        var size: String?
        var downloaded: Bool
        var isDefault: Bool

        enum CodingKeys: String, CodingKey {
            case id, name, provider, size, downloaded
            case isDefault = "default"
        }
    }

    static func defaultModel(requestedID: String? = nil) throws -> ModelOption {
        @Dependency(\.downloadClient) var downloadClient
        @Shared(.selectedModelID) var selectedModelID
        @Shared(.fileTranscriptionModelID) var fileTranscriptionModelID
        return try ModelResolution.resolve(
            requestedID: requestedID,
            selectedModelID: selectedModelID,
            fileTranscriptionModelID: fileTranscriptionModelID,
            isDownloaded: { downloadClient.isModelDownloaded($0) }
        )
    }

    // MARK: - Transcribe

    static func transcribe(_ options: TranscribeOptions, output: Int32) async throws {
        @Dependency(\.transcriptionClient) var transcriptionClient

        let model = try defaultModel(requestedID: options.modelID)
        let sourceURL = try inputURL(for: options.input)
        let status = StatusLine()
        defer { status.clear() }

        status.show("Preparing \(model.displayName)…")
        try await transcriptionClient.prepareModelIfNeeded(model)
        try Task.checkCancellation()

        status.show("Reading \(sourceURL.lastPathComponent)…")
        let audioURL = try await normalizedAudio(from: sourceURL)
        let duration = transcriptionClient.audioDurationSeconds(audioURL)
        try Task.checkCancellation()

        status.show("Transcribing \(formattedDuration(duration)) of audio with \(model.displayName)…")
        let text = try await transcriptionClient.transcribe(audioURL, model, .verbatim, nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try Task.checkCancellation()
        status.clear()

        let result: String
        if options.json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let payload = TranscriptPayload(model: model.rawValue, durationSeconds: duration, text: text)
            result = String(decoding: try encoder.encode(payload), as: UTF8.self) + "\n"
        } else {
            result = text + "\n"
        }

        if let outputPath = options.outputPath {
            let url = URL(fileURLWithPath: (outputPath as NSString).expandingTildeInPath).standardizedFileURL
            try Data(result.utf8).write(to: url, options: .atomic)
            printError("Wrote \(url.path)")
        } else {
            try write(result, to: output)
        }
    }

    struct TranscriptPayload: Encodable {
        var model: String
        var durationSeconds: Double
        var text: String
    }

    static func inputURL(for input: TranscribeOptions.Input) throws -> URL {
        switch input {
        case let .file(path):
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                throw CLIFailure("No file at '\(path)'.")
            }
            guard !isDirectory.boolValue else { throw CLIFailure("'\(path)' is a folder, not an audio file.") }
            return url
        case .standardInput:
            guard isatty(STDIN_FILENO) == 0 else {
                throw CLIUsageError("'-' reads audio from standard input. Pipe a file in, for example: cat memo.m4a | petal transcribe -")
            }
            let data = FileHandle.standardInput.readDataToEndOfFile()
            guard !data.isEmpty else { throw CLIFailure("Standard input has no audio.") }
            let url = TemporaryFiles.makeURL(pathExtension: "audio")
            try data.write(to: url)
            return url
        }
    }

    /// Matches the app's file import: decode any AVFoundation format to PCM, so each backend gets a plain file.
    static func normalizedAudio(from sourceURL: URL) async throws -> URL {
        let outputURL = TemporaryFiles.makeURL(pathExtension: "wav")
        try await Task.detached(priority: .userInitiated) {
            let input: AVAudioFile
            do {
                input = try AVAudioFile(forReading: sourceURL)
            } catch {
                throw CLIFailure("Cannot read '\(sourceURL.lastPathComponent)' as audio.")
            }
            let output = try AVAudioFile(forWriting: outputURL, settings: input.processingFormat.settings)
            let capacity = AVAudioFrameCount(min(input.processingFormat.sampleRate, 48_000))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: max(capacity, 1)) else {
                throw CLIFailure("Cannot read '\(sourceURL.lastPathComponent)' as audio.")
            }
            while input.framePosition < input.length {
                try Task.checkCancellation()
                try input.read(into: buffer)
                guard buffer.frameLength > 0 else { break }
                try output.write(from: buffer)
            }
        }.value
        return outputURL
    }

    static func formattedDuration(_ seconds: Double) -> String {
        Duration.seconds(seconds.rounded()).formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }

    // MARK: - Output

    static func write(_ text: String, to fd: Int32) throws {
        var bytes = Array(text.utf8)[...]
        while !bytes.isEmpty {
            let written = bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
            if written < 0 {
                if errno == EINTR { continue }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            bytes = bytes.dropFirst(written)
        }
    }

    static func printError(_ message: String) {
        try? write("petal: \(message)\n", to: STDERR_FILENO)
    }
}

struct CLIFailure: Error, LocalizedError {
    var message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Shows progress on stderr only for a terminal, so pipes and logs get no control characters.
struct StatusLine {
    private let isTerminal = isatty(STDERR_FILENO) != 0

    func show(_ text: String) {
        guard isTerminal else { return }
        try? PetalCLI.write("\r\u{1B}[2K\u{1B}[2m\(text)\u{1B}[0m", to: STDERR_FILENO)
    }

    func clear() {
        guard isTerminal else { return }
        try? PetalCLI.write("\r\u{1B}[2K", to: STDERR_FILENO)
    }
}

enum TemporaryFiles {
    private static let urls = Mutex<Set<URL>>([])

    static func makeURL(pathExtension: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "petal-cli-\(UUID().uuidString)")
            .appendingPathExtension(pathExtension)
        urls.withLock { _ = $0.insert(url) }
        return url
    }

    static func removeAll() {
        let all = urls.withLock { urls in
            defer { urls.removeAll() }
            return urls
        }
        for url in all {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

/// The first SIGINT or SIGTERM cancels the work and gives it a short time to stop. A second signal exits at once.
@MainActor
final class SignalTrap {
    private let task: Task<Int32, Never>
    private var sources: [DispatchSourceSignal] = []
    private var caughtSignal: Int32?

    init(task: Task<Int32, Never>) {
        self.task = task
    }

    func install() {
        for signalNumber in [SIGINT, SIGTERM, SIGHUP] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.handle(signalNumber) }
            }
            source.resume()
            sources.append(source)
        }
    }

    /// `exit` runs the MLX C++ static destructors while inference threads still run and crashes, so use `_exit`. All output is unbuffered.
    func exit(_ code: Int32) -> Never {
        TemporaryFiles.removeAll()
        Darwin._exit(caughtSignal.map { 128 + $0 } ?? code)
    }

    private func handle(_ signalNumber: Int32) {
        StatusLine().clear()
        guard caughtSignal == nil else { exit(128 + signalNumber) }
        caughtSignal = signalNumber
        PetalCLI.printError(signalNumber == SIGINT ? "Interrupted." : "Stopped.")
        task.cancel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            MainActor.assumeIsolated { self?.exit(128 + signalNumber) }
        }
    }
}
