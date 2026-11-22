import Dependencies
import DependenciesMacros
import Foundation
import os
import Shared

@DependencyClient
public struct LogClient: Sendable {
    public var debug: @Sendable (_ category: String, _ message: String) -> Void = { _, _ in }
    public var info: @Sendable (_ category: String, _ message: String) -> Void = { _, _ in }
    public var error: @Sendable (_ category: String, _ message: String) -> Void = { _, _ in }
    public var logFileURL: @Sendable () -> URL? = { nil }
}

extension LogClient: DependencyKey {
    public static var liveValue: Self {
        let fileWriter = LogFileWriter()

        return Self(
            debug: { category, message in
                Logger(subsystem: "com.optimalapps.petal", category: category)
                    .debug("\(message, privacy: .public)")
                fileWriter.write(level: "DEBUG", category: category, message: message)
            },
            info: { category, message in
                Logger(subsystem: "com.optimalapps.petal", category: category)
                    .info("\(message, privacy: .public)")
                fileWriter.write(level: "INFO", category: category, message: message)
            },
            error: { category, message in
                Logger(subsystem: "com.optimalapps.petal", category: category)
                    .error("\(message, privacy: .public)")
                fileWriter.write(level: "ERROR", category: category, message: message)
            },
            logFileURL: {
                fileWriter.currentFileURLIfExists()
            }
        )
    }
}

extension LogClient: TestDependencyKey {
    public static var testValue: Self {
        Self()
    }
}

public extension DependencyValues {
    var logClient: LogClient {
        get { self[LogClient.self] }
        set { self[LogClient.self] = newValue }
    }
}

private final class LogFileWriter: @unchecked Sendable {
    @SharedReader(.logsEnabled) private var logsEnabled
    private static let logsDirectory = PetalPaths.documents.appending(path: "logs", directoryHint: .isDirectory)

    private let queue = DispatchQueue(label: "com.optimalapps.petal.log-file-writer", qos: .utility)
    private var fileHandle: FileHandle?
    let currentFileURL: URL

    init() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let fileName = "petal-\(formatter.string(from: Date())).log"
        let url = Self.logsDirectory.appendingPathComponent(fileName)

        self.currentFileURL = url
    }

    func currentFileURLIfExists() -> URL? {
        let url = currentFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    func write(level: String, category: String, message: String) {
        guard logsEnabled else { return }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date())
        let line = "[\(timestamp)] [\(level)] [\(category)] \(message)\n"

        guard let data = line.data(using: .utf8) else { return }
        queue.async {
            let fm = FileManager.default
            try? fm.createDirectory(at: Self.logsDirectory, withIntermediateDirectories: true)
            if !fm.fileExists(atPath: self.currentFileURL.path) {
                _ = fm.createFile(atPath: self.currentFileURL.path, contents: nil)
            }
            if self.fileHandle == nil {
                self.fileHandle = try? FileHandle(forWritingTo: self.currentFileURL)
                _ = try? self.fileHandle?.seekToEnd()
            }
            self.fileHandle?.write(data)
        }
    }

}
