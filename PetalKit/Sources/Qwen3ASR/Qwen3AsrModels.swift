@preconcurrency import CoreML
import Foundation
import OSLog

private let logger = Logger(subsystem: "FluidAudio", category: "Qwen3AsrModels")

/// Qwen3-ASR model variant (precision).
public enum Qwen3AsrVariant: String, CaseIterable, Sendable {
    /// Full precision (FP16 weights). Best speed, ~1.75 GB.
    case f32
    /// Int8 quantized weights. Half the RAM (~900 MB), same quality.
    case int8

    var folderName: String { "qwen3-asr-0.6b-coreml/\(rawValue)" }
}

// MARK: - Qwen3-ASR CoreML Model Container (2-model pipeline)

/// Holds CoreML model components for the optimized 2-model Qwen3-ASR pipeline.
///
/// This uses Swift-side embedding lookup from a preloaded weight matrix,
/// eliminating the embedding CoreML model. Reduces CoreML calls from 3 to 2 per token.
///
/// Components:
/// - `audioEncoder`: mel spectrogram -> 1024-dim audio features (single window)
/// - `decoderStateful`: stateful decoder with fused lmHead (outputs logits directly)
/// - `embeddingWeights`: [151936, 1024] float16 matrix for Swift-side embedding lookup
@available(macOS 15, iOS 18, *)
public struct Qwen3AsrModels: Sendable {
    public let audioEncoder: MLModel
    public let decoderStateful: MLModel
    public let embeddingWeights: EmbeddingWeights
    public let vocabulary: [Int: String]

    /// Load Qwen3-ASR models (2-model pipeline with Swift-side embedding) from a directory.
    ///
    /// Expected directory structure:
    /// ```
    /// qwen3-asr/
    ///   qwen3_asr_audio_encoder_v2.mlmodelc
    ///   qwen3_asr_decoder_stateful.mlmodelc
    ///   qwen3_asr_embeddings.bin  (float16 embedding weights)
    ///   vocab.json
    /// ```
    public static func load(
        from directory: URL,
        computeUnits: MLComputeUnits = .all
    ) async throws -> Qwen3AsrModels {
        let modelConfig = MLModelConfiguration()
        modelConfig.computeUnits = computeUnits

        logger.info("Loading Qwen3-ASR models (2-model pipeline) from \(directory.path)")
        let start = CFAbsoluteTimeGetCurrent()

        // Load audio encoder
        let audioEncoder = try await loadModel(
            named: "qwen3_asr_audio_encoder_v2",
            from: directory,
            configuration: modelConfig
        )

        // On macOS 27 the GPU attention kernel aborts the process for this stateful decoder, and the Neural Engine rejects it.
        let decoderConfig = MLModelConfiguration()
        if #available(macOS 27, *), computeUnits == .all {
            decoderConfig.computeUnits = .cpuOnly
        } else {
            decoderConfig.computeUnits = computeUnits
        }

        // Load stateful decoder (with fused lmHead)
        let decoderStateful = try await loadModel(
            named: "qwen3_asr_decoder_stateful",
            from: directory,
            configuration: decoderConfig
        )

        // Load embedding weights for Swift-side lookup
        let embeddingWeights = try loadEmbeddingWeights(from: directory)

        let elapsed = CFAbsoluteTimeGetCurrent() - start
        logger.info("Loaded Qwen3-ASR models (2-model) in \(String(format: "%.2f", elapsed))s")

        // Load vocabulary from tokenizer
        let vocabulary = try loadVocabulary(from: directory)

        return Qwen3AsrModels(
            audioEncoder: audioEncoder,
            decoderStateful: decoderStateful,
            embeddingWeights: embeddingWeights,
            vocabulary: vocabulary
        )
    }

    /// Check if all required model files exist locally.
    public static func modelsExist(at directory: URL) -> Bool {
        let fm = FileManager.default
        let requiredFiles = [
            "qwen3_asr_audio_encoder_v2.mlmodelc",
            "qwen3_asr_decoder_stateful.mlmodelc",
            "qwen3_asr_embeddings.bin",
            "vocab.json",
        ]
        return requiredFiles.allSatisfy { file in
            fm.fileExists(atPath: directory.appendingPathComponent(file).path)
        }
    }

    /// Root directory for all FluidAudio model caches.
    private static func modelsRootDirectory() -> URL {
        guard
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first
        else {
            // Fallback to temporary directory if application support unavailable
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("FluidAudio", isDirectory: true)
                .appendingPathComponent("Models", isDirectory: true)
        }
        return
            appSupport
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    /// Default cache directory for Qwen3-ASR models.
    public static func defaultCacheDirectory(variant: Qwen3AsrVariant = .f32) -> URL {
        modelsRootDirectory()
            .appendingPathComponent(variant.folderName, isDirectory: true)
    }

    // MARK: Private

    private static func loadModel(
        named name: String,
        from directory: URL,
        configuration: MLModelConfiguration
    ) async throws -> MLModel {
        // Try .mlmodelc first (pre-compiled), then compile .mlpackage on the fly
        let compiledPath = directory.appendingPathComponent("\(name).mlmodelc")
        let packagePath = directory.appendingPathComponent("\(name).mlpackage")

        let modelURL: URL
        if FileManager.default.fileExists(atPath: compiledPath.path) {
            modelURL = compiledPath
        } else if FileManager.default.fileExists(atPath: packagePath.path) {
            // .mlpackage must be compiled to .mlmodelc before loading
            logger.info("Compiling \(name).mlpackage -> .mlmodelc ...")
            let compileStart = CFAbsoluteTimeGetCurrent()
            let compiledURL = try await MLModel.compileModel(at: packagePath)
            let compileElapsed = CFAbsoluteTimeGetCurrent() - compileStart
            logger.info("  \(name): compiled in \(String(format: "%.2f", compileElapsed))s")

            // Move compiled model next to the package for caching
            try? FileManager.default.removeItem(at: compiledPath)
            try FileManager.default.copyItem(at: compiledURL, to: compiledPath)
            // Clean up the temp compiled model
            try? FileManager.default.removeItem(at: compiledURL)

            modelURL = compiledPath
        } else {
            throw Qwen3AsrError.modelNotFound(name)
        }

        let start = CFAbsoluteTimeGetCurrent()
        let model = try await MLModel.load(contentsOf: modelURL, configuration: configuration)
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        logger.debug("  \(name): loaded in \(String(format: "%.2f", elapsed))s")
        return model
    }

    private static func loadEmbeddingWeights(from directory: URL) throws -> EmbeddingWeights {
        let path = directory.appendingPathComponent("qwen3_asr_embeddings.bin")
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw Qwen3AsrError.modelNotFound("qwen3_asr_embeddings.bin")
        }

        let start = CFAbsoluteTimeGetCurrent()
        let weights = try EmbeddingWeights(contentsOf: path)
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        logger.info(
            "Loaded embedding weights in \(String(format: "%.2f", elapsed))s (\(weights.vocabSize) x \(weights.hiddenSize))"
        )
        return weights
    }

    private static func loadVocabulary(from directory: URL) throws -> [Int: String] {
        let vocabPath = directory.appendingPathComponent("vocab.json")
        guard FileManager.default.fileExists(atPath: vocabPath.path) else {
            throw Qwen3AsrError.modelNotFound("vocab.json")
        }

        let data = try Data(contentsOf: vocabPath)
        guard let stringToId = try JSONSerialization.jsonObject(with: data) as? [String: Int] else {
            throw Qwen3AsrError.invalidVocabulary
        }

        // Invert: token string -> token ID becomes token ID -> token string
        var idToString: [Int: String] = [:]
        idToString.reserveCapacity(stringToId.count)
        for (token, id) in stringToId {
            idToString[id] = token
        }
        logger.info("Loaded vocabulary: \(idToString.count) tokens")
        return idToString
    }
}

// MARK: - Embedding Weights

/// Preloaded embedding weights for Swift-side token embedding lookup.
/// Eliminates the need for a separate embedding CoreML model.
public final class EmbeddingWeights: Sendable {
    public let vocabSize: Int
    public let hiddenSize: Int
    private let data: Data

    /// Load embedding weights from a binary file.
    /// Format: uint32 vocabSize, uint32 hiddenSize, then float16[vocabSize * hiddenSize]
    public init(contentsOf url: URL) throws {
        let fileData = try Data(contentsOf: url)
        guard fileData.count >= 8 else {
            throw Qwen3AsrError.invalidVocabulary
        }

        // Read header
        let vocab = fileData.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self) }
        let hidden = fileData.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) }
        self.vocabSize = Int(vocab)
        self.hiddenSize = Int(hidden)

        // Validate against config
        guard vocabSize == Qwen3AsrConfig.vocabSize else {
            throw Qwen3AsrError.generationFailed(
                "Embedding vocab size \(vocabSize) != config \(Qwen3AsrConfig.vocabSize)"
            )
        }
        guard hiddenSize == Qwen3AsrConfig.hiddenSize else {
            throw Qwen3AsrError.generationFailed(
                "Embedding hidden size \(hiddenSize) != config \(Qwen3AsrConfig.hiddenSize)"
            )
        }

        // Verify file size
        let expectedSize = 8 + vocabSize * hiddenSize * 2  // header + float16 data
        guard fileData.count == expectedSize else {
            throw Qwen3AsrError.generationFailed(
                "Embedding file size mismatch: expected \(expectedSize), got \(fileData.count)"
            )
        }

        self.data = fileData
    }

    /// Get embedding vector for a token ID.
    /// Returns float32 array of length hiddenSize.
    public func embedding(for tokenId: Int) -> [Float] {
        guard tokenId >= 0, tokenId < vocabSize else {
            return [Float](repeating: 0, count: hiddenSize)
        }

        let offset = 8 + tokenId * hiddenSize * 2  // header + token offset (float16)
        var result = [Float](repeating: 0, count: hiddenSize)

        #if arch(arm64)
        data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
            let f16Ptr = ptr.baseAddress!.advanced(by: offset)
                .assumingMemoryBound(to: Float16.self)

            for i in 0..<hiddenSize {
                result[i] = Float(f16Ptr[i])
            }
        }
        #else
        // Float16 is only available on Apple Silicon
        fatalError("Qwen3-ASR requires Apple Silicon (arm64)")
        #endif

        return result
    }

    /// Get embeddings for multiple token IDs.
    /// Returns [seqLen][hiddenSize] array.
    public func embeddings(for tokenIds: [Int32]) -> [[Float]] {
        tokenIds.map { embedding(for: Int($0)) }
    }
}

// MARK: - Errors

public enum Qwen3AsrError: Error, LocalizedError {
    case modelNotFound(String)
    case invalidVocabulary
    case encoderFailed(String)
    case decoderFailed(String)
    case generationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .modelNotFound(let name):
            return "Qwen3-ASR model not found: \(name)"
        case .invalidVocabulary:
            return "Invalid vocabulary file"
        case .encoderFailed(let detail):
            return "Audio encoder failed: \(detail)"
        case .decoderFailed(let detail):
            return "Decoder failed: \(detail)"
        case .generationFailed(let detail):
            return "Generation failed: \(detail)"
        }
    }
}
