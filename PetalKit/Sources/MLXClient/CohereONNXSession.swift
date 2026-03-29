import Accelerate
import CoreML
import Foundation
import OnnxRuntimeBindings

/// Hybrid CoreML encoder + ONNX decoder for Cohere Transcribe.
///
/// The encoder (1.9B params, 95% of model) runs on CoreML with ANE acceleration.
/// The decoder (153M params) runs on ONNX Runtime with KV cache on CPU.
final class CohereONNXSession {
    private let encoderModel: MLModel
    private let decoderSession: ORTSession
    private let env: ORTEnv
    private let tokenizer: CohereTokenizer
    /// Decoder projection weights [1280, 1024] + bias [1024] to project encoder 1280→1024
    private let projWeight: [Float] // [1024, 1280] row-major (transposed for matmul)
    private let projBias: [Float]   // [1024]

    private let decoderStartTokenId: Int
    private let eosTokenId: Int
    private let maxNewTokens: Int
    private let numDecoderLayers = 8
    private let numHeads = 8
    private let headDim = 128

    init(modelDirectory: URL, variant: CohereONNXVariant = .q4f16) throws {
        env = try ORTEnv(loggingLevel: .warning)

        let genConfigURL = modelDirectory.appendingPathComponent("generation_config.json")
        let genData = try Data(contentsOf: genConfigURL)
        let genConfig = try JSONSerialization.jsonObject(with: genData) as? [String: Any] ?? [:]

        decoderStartTokenId = genConfig["decoder_start_token_id"] as? Int ?? 13764
        eosTokenId = genConfig["eos_token_id"] as? Int ?? 3
        maxNewTokens = 256

        tokenizer = try CohereTokenizer(modelDirectory: modelDirectory)

        // Load decoder projection weights (1280→1024)
        let weightURL = modelDirectory.appendingPathComponent("decoder_proj_weight.bin")
        let biasURL = modelDirectory.appendingPathComponent("decoder_proj_bias.bin")
        let weightData = try Data(contentsOf: weightURL)
        let biasData = try Data(contentsOf: biasURL)
        projWeight = weightData.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        projBias = biasData.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }

        // CoreML encoder — compile .mlpackage to .mlmodelc if needed
        let mlpackagePath = modelDirectory.appendingPathComponent("cohere_encoder.mlpackage")
        let compiledPath = modelDirectory.appendingPathComponent("cohere_encoder.mlmodelc")

        if FileManager.default.fileExists(atPath: compiledPath.path) {
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine
            encoderModel = try MLModel(contentsOf: compiledPath, configuration: config)
        } else {
            let compiled = try MLModel.compileModel(at: mlpackagePath)
            // Move compiled model next to source for caching
            try? FileManager.default.moveItem(at: compiled, to: compiledPath)
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine
            encoderModel = try MLModel(contentsOf: compiledPath, configuration: config)
        }

        // ONNX decoder
        let decoderPath = CohereONNXCache.resolveModelPath(
            variant: variant, filename: variant.decoderModelFilename
        )
        let decoderOptions = try ORTSessionOptions()
        try decoderOptions.setGraphOptimizationLevel(.all)
        decoderSession = try ORTSession(env: env, modelPath: decoderPath, sessionOptions: decoderOptions)
    }

    func transcribe(audioURL: URL, language: String = "en") throws -> String {
        let features = try CoherePreprocessor.extractFeatures(from: audioURL)
        guard features.timeFrames > 0 else {
            throw CohereONNXError.emptyAudio
        }

        let encoderOutput = try runCoreMLEncoder(features: features)

        let promptTokens = tokenizer.buildPromptTokenIds(
            decoderStartTokenId: decoderStartTokenId,
            language: language
        )

        let outputTokens = try greedyDecode(
            encoderOutput: encoderOutput,
            promptTokens: promptTokens
        )

        let text = tokenizer.decode(tokenIds: outputTokens)
        guard !text.isEmpty else {
            throw CohereONNXError.emptyTranscript
        }
        return text
    }

    // MARK: - CoreML Encoder

    private struct EncoderOutput {
        /// Raw float16 data for the ONNX decoder, shape [1, enc_seq, 1280]
        let hiddenStatesData: NSMutableData
        let encoderSeqLen: Int
        /// Float16 shape for ONNX decoder input
        let shape: [NSNumber]
    }

    private func runCoreMLEncoder(features: CoherePreprocessor.MelFeatures) throws -> EncoderOutput {
        // CoreML encoder expects mel_features [1, T, 128] as MLMultiArray
        let inputArray = try MLMultiArray(shape: [1, features.timeFrames as NSNumber, 128], dataType: .float32)

        // Transpose from [128, T] (row-major mel-first) to [1, T, 128] (time-first)
        let ptr = inputArray.dataPointer.assumingMemoryBound(to: Float.self)
        for t in 0..<features.timeFrames {
            for m in 0..<features.nMels {
                ptr[t * features.nMels + m] = features.data[m * features.timeFrames + t]
            }
        }

        let input = try MLDictionaryFeatureProvider(dictionary: ["mel_features": inputArray])
        let result = try encoderModel.prediction(from: input)

        guard let outputArray = result.featureValue(for: "encoder_output")?.multiArrayValue else {
            throw CohereONNXError.encoderFailed
        }

        // outputArray is [1, enc_seq, 1280] in float16
        let encoderSeqLen = outputArray.shape[1].intValue
        let totalElements = outputArray.shape.reduce(1) { $0 * $1.intValue }
        let byteCount = totalElements * 2 // float16 = 2 bytes

        let data = NSMutableData(bytes: outputArray.dataPointer, length: byteCount)
        let shape: [NSNumber] = [1, NSNumber(value: encoderSeqLen), 1280]

        return EncoderOutput(hiddenStatesData: data, encoderSeqLen: encoderSeqLen, shape: shape)
    }

    // MARK: - ONNX Decoder (with KV cache)

    private lazy var presentOutputNames: Set<String> = {
        var names = Set<String>()
        for layer in 0..<numDecoderLayers {
            for kind in ["decoder", "encoder"] {
                for kv in ["key", "value"] {
                    names.insert("present.\(layer).\(kind).\(kv)")
                }
            }
        }
        return names
    }()

    private func greedyDecode(
        encoderOutput: EncoderOutput,
        promptTokens: [Int]
    ) throws -> [Int] {
        // Project encoder output 1280→1024 and convert fp16→fp32
        let projectedData = projectEncoderOutput(encoderOutput)
        let projectedShape: [NSNumber] = [1, NSNumber(value: encoderOutput.encoderSeqLen), 1024]
        let encoderTensor = try ORTValue(
            tensorData: projectedData,
            elementType: .float,
            shape: projectedShape
        )

        var kvCache: [String: (data: NSMutableData, shape: [NSNumber])]? = nil
        var allTokens = promptTokens
        let allOutputNames = presentOutputNames.union(["logits"])

        for step in 0..<maxNewTokens {
            let isFirstStep = (step == 0)
            let inputTokens: [Int64]
            let seqLen: Int

            if isFirstStep {
                inputTokens = allTokens.map { Int64($0) }
                seqLen = allTokens.count
            } else {
                inputTokens = [Int64(allTokens.last!)]
                seqLen = 1
            }

            // input_ids
            var ids = inputTokens
            let idsData = NSMutableData(bytes: &ids, length: ids.count * MemoryLayout<Int64>.size)
            let idsTensor = try ORTValue(
                tensorData: idsData, elementType: .int64,
                shape: [1, NSNumber(value: seqLen)]
            )

            // attention_mask
            let pastDecoderLen = isFirstStep ? 0 : (kvCache?["present.0.decoder.key"]?.shape[2].intValue ?? 0)
            let totalLen = pastDecoderLen + seqLen
            var attMask = [Int64](repeating: 1, count: totalLen)
            let attData = NSMutableData(bytes: &attMask, length: attMask.count * MemoryLayout<Int64>.size)
            let attTensor = try ORTValue(
                tensorData: attData, elementType: .int64,
                shape: [1, NSNumber(value: totalLen)]
            )

            // position_ids
            var posIds: [Int64] = isFirstStep
                ? (0..<Int64(seqLen)).map { $0 }
                : [Int64(pastDecoderLen)]
            let posData = NSMutableData(bytes: &posIds, length: posIds.count * MemoryLayout<Int64>.size)
            let posTensor = try ORTValue(
                tensorData: posData, elementType: .int64,
                shape: [1, NSNumber(value: seqLen)]
            )

            // num_logits_to_keep = 1
            var numLogits: Int64 = 1
            let nlData = NSMutableData(bytes: &numLogits, length: MemoryLayout<Int64>.size)
            let nlTensor = try ORTValue(tensorData: nlData, elementType: .int64, shape: [])

            var inputs: [String: ORTValue] = [
                "input_ids": idsTensor,
                "attention_mask": attTensor,
                "position_ids": posTensor,
                "num_logits_to_keep": nlTensor,
                "encoder_hidden_states": encoderTensor,
            ]

            // KV cache
            let emptyData = NSMutableData()
            let emptyShape: [NSNumber] = [1, NSNumber(value: numHeads), 0, NSNumber(value: headDim)]
            for layer in 0..<numDecoderLayers {
                for kind in ["decoder", "encoder"] {
                    for kv in ["key", "value"] {
                        let pastName = "past_key_values.\(layer).\(kind).\(kv)"
                        let presentName = "present.\(layer).\(kind).\(kv)"
                        if let cached = kvCache?[presentName] {
                            inputs[pastName] = try ORTValue(
                                tensorData: cached.data, elementType: .float16, shape: cached.shape
                            )
                        } else {
                            inputs[pastName] = try ORTValue(
                                tensorData: emptyData, elementType: .float16, shape: emptyShape
                            )
                        }
                    }
                }
            }

            let results = try decoderSession.run(
                withInputs: inputs, outputNames: allOutputNames, runOptions: nil
            )

            guard let logitsValue = results["logits"] else {
                throw CohereONNXError.decoderFailed
            }
            let nextToken = argmaxFloat16(data: try logitsValue.tensorData(), count: 16384)

            if nextToken == eosTokenId { break }
            allTokens.append(nextToken)

            // Update KV cache
            var newCache = [String: (data: NSMutableData, shape: [NSNumber])]()
            for name in presentOutputNames {
                guard let val = results[name] else { continue }
                newCache[name] = (
                    data: try val.tensorData(),
                    shape: try val.tensorTypeAndShapeInfo().shape
                )
            }
            kvCache = newCache
        }

        return Array(allTokens.dropFirst(promptTokens.count))
    }

    // MARK: - Helpers

    /// Projects encoder output from 1280→1024 using the decoder's proj layer.
    /// Input: fp16 [1, T, 1280], Output: fp32 [1, T, 1024]
    private func projectEncoderOutput(_ enc: EncoderOutput) -> NSMutableData {
        let T = enc.encoderSeqLen
        let inDim = 1280
        let outDim = 1024

        // Convert fp16 encoder output to fp32
        let fp32 = convertFloat16ToFloat32(enc.hiddenStatesData)
        let src = fp32.bytes.assumingMemoryBound(to: Float.self)

        // out[t] = src[t] @ projWeight^T + projBias
        // projWeight is [1024, 1280] row-major
        let result = NSMutableData(length: T * outDim * MemoryLayout<Float>.size)!
        let dst = result.mutableBytes.assumingMemoryBound(to: Float.self)

        // Matrix multiply: [T, 1280] × [1280, 1024] = [T, 1024]
        // projWeight is [1024, 1280], so we use CblasTrans on B
        cblas_sgemm(
            CblasRowMajor, CblasNoTrans, CblasTrans,
            Int32(T), Int32(outDim), Int32(inDim),
            1.0,
            src, Int32(inDim),
            projWeight, Int32(inDim),
            0.0,
            dst, Int32(outDim)
        )

        // Add bias
        for t in 0..<T {
            let offset = t * outDim
            for d in 0..<outDim {
                dst[offset + d] += projBias[d]
            }
        }

        return result
    }

    private func convertFloat16ToFloat32(_ fp16Data: NSMutableData) -> NSMutableData {
        let count = fp16Data.length / 2
        let src = fp16Data.bytes.assumingMemoryBound(to: UInt16.self)
        let result = NSMutableData(length: count * 4)!
        let dst = result.mutableBytes.assumingMemoryBound(to: Float.self)
        for i in 0..<count {
            dst[i] = float16ToFloat32(src[i])
        }
        return result
    }

    private func argmaxFloat16(data: NSMutableData, count: Int) -> Int {
        let ptr = data.bytes.assumingMemoryBound(to: UInt16.self)
        var maxIdx = 0
        var maxVal = float16ToFloat32(ptr[0])
        for i in 1..<count {
            let val = float16ToFloat32(ptr[i])
            if val > maxVal {
                maxVal = val
                maxIdx = i
            }
        }
        return maxIdx
    }

    private func float16ToFloat32(_ h: UInt16) -> Float {
        let sign = (h >> 15) & 0x1
        let exp = (h >> 10) & 0x1F
        let frac = h & 0x3FF

        if exp == 0 {
            if frac == 0 { return sign == 0 ? 0.0 : -0.0 }
            let val = Float(frac) / 1024.0 * pow(2.0, -14.0)
            return sign == 0 ? val : -val
        } else if exp == 31 {
            return frac == 0 ? (sign == 0 ? Float.infinity : -Float.infinity) : Float.nan
        }

        let val = (1.0 + Float(frac) / 1024.0) * pow(2.0, Float(Int(exp) - 15))
        return sign == 0 ? val : -val
    }
}

enum CohereONNXError: LocalizedError {
    case emptyAudio
    case encoderFailed
    case decoderFailed
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .emptyAudio: "No audio data to transcribe."
        case .encoderFailed: "Cohere encoder failed to produce output."
        case .decoderFailed: "Cohere decoder failed to produce output."
        case .emptyTranscript: "No speech detected."
        }
    }
}
