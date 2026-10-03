import Foundation

enum RecordingFiles {
    static let minimumUsefulBytes = 16_384

    static var directory: URL {
        let url = URL.applicationSupportDirectory.appending(path: "Petal/Recordings", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func newURL(extension pathExtension: String) -> URL {
        directory.appending(path: "petal-\(UUID().uuidString).\(pathExtension)")
    }

    static func unfinished(in directory: URL = directory, excluding active: Set<URL>) -> [URL] {
        let manager = FileManager.default
        let keys: [URLResourceKey] = [.fileSizeKey, .creationDateKey]
        let files = (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        return files
            .filter { ["wav", "m4a"].contains($0.pathExtension.lowercased()) && !active.contains($0.standardizedFileURL) }
            .compactMap { url -> (URL, Date)? in
                let values = try? url.resourceValues(forKeys: Set(keys))
                guard (values?.fileSize ?? 0) >= minimumUsefulBytes else {
                    try? manager.removeItem(at: url)
                    return nil
                }
                if url.pathExtension.lowercased() == "wav" {
                    try? WAVHeaderRepair.repair(url)
                }
                return (url, values?.creationDate ?? .distantPast)
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }
}
