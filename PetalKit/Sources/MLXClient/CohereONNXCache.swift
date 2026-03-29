import Foundation
import VoxtralCore

/// Root directory for all Petal data: ~/Documents/petal/
private let petalModelsDirectory: URL = FileManager.default
    .urls(for: .documentDirectory, in: .userDomainMask).first!
    .appendingPathComponent("petal")
    .appendingPathComponent("models")

enum CohereONNXVariant: String, Sendable {
    case q4f16
    case fp16

    /// CoreML encoder is shared across variants (converted from FP32 PyTorch).
    static let coremlEncoderDir = "cohere_encoder.mlpackage"

    var decoderFiles: [String] {
        switch self {
        case .q4f16:
            return ["decoder_model_merged_q4f16.onnx", "decoder_model_merged_q4f16.onnx_data"]
        case .fp16:
            return ["decoder_model_merged_fp16.onnx", "decoder_model_merged_fp16.onnx_data"]
        }
    }

    var decoderModelFilename: String {
        switch self {
        case .q4f16: "decoder_model_merged_q4f16.onnx"
        case .fp16: "decoder_model_merged_fp16.onnx"
        }
    }

    /// All files needed: CoreML encoder + ONNX decoder
    var allModelFiles: [String] { decoderFiles }
}

enum CohereONNXCache {
    static let repoID = "onnx-community/cohere-transcribe-03-2026-ONNX"

    static let configFiles = [
        "config.json",
        "generation_config.json",
        "preprocessor_config.json",
        "tokenizer.json",
        "tokenizer_config.json",
        "decoder_proj_weight.bin",
        "decoder_proj_bias.bin",
    ]

    static var modelDirectory: URL {
        petalModelsDirectory
            .appendingPathComponent("onnx-community")
            .appendingPathComponent("cohere-transcribe-03-2026-ONNX")
    }

    // MARK: - Variant-aware API

    static func isModelDownloaded(variant: CohereONNXVariant = .q4f16) -> Bool {
        let dir = modelDirectory
        let onnxDir = dir.appendingPathComponent("onnx")
        let fm = FileManager.default

        // Config files at top level
        for file in configFiles {
            if !fm.fileExists(atPath: dir.appendingPathComponent(file).path) {
                return false
            }
        }

        // CoreML encoder (mlpackage or compiled mlmodelc)
        let mlpackage = dir.appendingPathComponent(CohereONNXVariant.coremlEncoderDir).path
        let mlmodelc = dir.appendingPathComponent("cohere_encoder.mlmodelc").path
        if !fm.fileExists(atPath: mlpackage) && !fm.fileExists(atPath: mlmodelc) {
            return false
        }

        // ONNX decoder files
        for file in variant.decoderFiles {
            let topLevel = dir.appendingPathComponent(file).path
            let inSubfolder = onnxDir.appendingPathComponent(file).path
            if !fm.fileExists(atPath: topLevel) && !fm.fileExists(atPath: inSubfolder) {
                return false
            }
        }

        return true
    }

    static func modelDirectoryURL(variant: CohereONNXVariant = .q4f16) -> URL? {
        isModelDownloaded(variant: variant) ? modelDirectory : nil
    }

    static func downloadIfNeeded(
        variant: CohereONNXVariant = .q4f16,
        progress: @escaping @Sendable (Double, String) -> Void
    ) async throws {
        if isModelDownloaded(variant: variant) {
            progress(1, "Model already downloaded")
            return
        }

        progress(0, "Downloading Cohere Transcribe (\(variant.rawValue)) model...")

        let allowedFiles = Set(variant.allModelFiles + configFiles)

        try await ModelDownloader.downloadFromHuggingFace(
            repoId: repoID,
            subfolder: nil,
            destination: modelDirectory,
            fileFilter: { path in
                let filename = (path as NSString).lastPathComponent
                if allowedFiles.contains(filename) {
                    return true
                }
                if path.hasPrefix("onnx/") {
                    let onnxFilename = String(path.dropFirst("onnx/".count))
                    return allowedFiles.contains(onnxFilename)
                }
                return false
            },
            progress: progress
        )

        progress(1, "Download complete")
    }

    static func deleteModel(variant: CohereONNXVariant = .q4f16) throws {
        let dir = modelDirectory
        let onnxDir = dir.appendingPathComponent("onnx")
        let fm = FileManager.default

        // Delete variant-specific ONNX files
        for file in variant.allModelFiles {
            for candidate in [dir.appendingPathComponent(file), onnxDir.appendingPathComponent(file)] {
                if fm.fileExists(atPath: candidate.path) {
                    try fm.removeItem(at: candidate)
                }
            }
        }

        // If no other variant files remain, clean up the entire directory
        let otherVariant: CohereONNXVariant = variant == .q4f16 ? .fp16 : .q4f16
        if !isModelDownloaded(variant: otherVariant) {
            // Check if any ONNX files remain
            let onnxContents = (try? fm.contentsOfDirectory(atPath: onnxDir.path)) ?? []
            let hasOtherONNX = onnxContents.contains { $0.hasSuffix(".onnx") || $0.hasSuffix(".onnx_data") }
            if !hasOtherONNX && fm.fileExists(atPath: dir.path) {
                try fm.removeItem(at: dir)
            }
        }
    }

    static func resolveModelPath(variant: CohereONNXVariant, filename: String) -> String {
        let onnxSubfolder = modelDirectory.appendingPathComponent("onnx").appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: onnxSubfolder.path) {
            return onnxSubfolder.path
        }
        return modelDirectory.appendingPathComponent(filename).path
    }
}
