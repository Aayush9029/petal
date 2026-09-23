import Foundation
import VoxtralCore

enum S1MiniModelFiles {
    static let info = VoxtralModelInfo(
        id: "s1-mini-mlx-8bit",
        repoId: "Aayush9029/s1-mini-mlx-8bit",
        name: "S1-mini by Superwhisper",
        description: "Transcript cleanup model",
        size: "619 MB",
        quantization: "MLX 8-bit",
        parameters: "0.6B"
    )

    static var directory: URL? {
        ModelDownloader.findModelPath(for: info)
    }
}
