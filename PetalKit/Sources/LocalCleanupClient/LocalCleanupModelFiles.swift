import Foundation
import Shared
import VoxtralCore

enum LocalCleanupModelFiles {
    static func info(for model: CleanupModel) -> VoxtralModelInfo? {
        switch model {
        case .s1Mini:
            VoxtralModelInfo(
                id: "s1-mini-mlx-8bit",
                repoId: "Aayush9029/s1-mini-mlx-8bit",
                name: "S1-mini by Superwhisper",
                description: "Transcript cleanup model",
                size: "619 MB",
                quantization: "MLX 8-bit",
                parameters: "0.6B"
            )
        case .petalW1:
            VoxtralModelInfo(
                id: "petal-w1",
                repoId: "Aayush9029/petal-w1",
                name: "Petal W1",
                description: "Transcript cleanup model fine-tuned from Qwen3.5-0.8B",
                size: "782 MB",
                quantization: "MLX 8-bit",
                parameters: "0.8B"
            )
        case .off, .appleIntelligence:
            nil
        }
    }

    static func directory(for model: CleanupModel) -> URL? {
        info(for: model).flatMap(ModelDownloader.findModelPath(for:))
    }

    /// The Hugging Face tag that the app expects. A local copy without it is replaced in the background.
    static func revision(for model: CleanupModel) -> String? {
        model == .petalW1 ? "v1.1" : nil
    }

    private static let revisionFile = ".petal-revision"

    static func isOutdated(_ model: CleanupModel) -> Bool {
        guard let revision = revision(for: model), let directory = directory(for: model) else { return false }
        let recorded = try? String(contentsOf: directory.appending(path: revisionFile), encoding: .utf8)
        return recorded?.trimmingCharacters(in: .whitespacesAndNewlines) != revision
    }

    static func recordRevision(for model: CleanupModel) {
        guard let revision = revision(for: model), let directory = directory(for: model) else { return }
        try? revision.write(to: directory.appending(path: revisionFile), atomically: true, encoding: .utf8)
    }
}
