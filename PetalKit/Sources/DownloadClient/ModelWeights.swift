import Foundation

package enum ModelWeights {
    package static func hasContents(_ url: URL) -> Bool {
        guard let values = try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) else { return false }
        return values.isRegularFile == true && (values.fileSize ?? 0) > 0
    }

    package static func areComplete(at directory: URL) -> Bool {
        guard hasContents(directory.appending(path: "config.json")),
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return false }
        let weights = files.filter { $0.pathExtension == "safetensors" }
        guard !weights.isEmpty, weights.allSatisfy(hasContents) else { return false }

        let index = directory.appending(path: "model.safetensors.index.json")
        if FileManager.default.fileExists(atPath: index.path) {
            struct Index: Decodable { let weightMap: [String: String] }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            guard let data = try? Data(contentsOf: index),
                  let shards = try? decoder.decode(Index.self, from: data),
                  !shards.weightMap.isEmpty,
                  Set(shards.weightMap.values).isSubset(of: Set(weights.map(\.lastPathComponent)))
            else { return false }
        }
        return !hasIncompleteTransfer(at: directory)
    }

    static func hasIncompleteTransfer(at directory: URL) -> Bool {
        guard let contents = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else { return true }
        // aria2 preallocates the output and keeps a control file until completion.
        return contents.contains { ($0 as? URL)?.pathExtension == "aria2" }
    }
}
