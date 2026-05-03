import Accelerate
@preconcurrency import CoreML
import FluidAudio
import Foundation
import OSLog

private let qwen17Logger = Logger(subsystem: "Petal", category: "Qwen3ASR17B")

enum Qwen3ASR17BCoreMLModels {
    static let repoID = "weiren119/Qwen3-ASR-1.7B-CoreML"
    static let encoderName = "qwen3_asr_encoder_int8"
    static let decoderName = "qwen3_asr_decoder_f32_anemll_int8-mixed"
    static let embeddingsFile = "qwen3_asr_embeddings.bin"
    static let vocabularyFile = "vocab.json"

    static func defaultCacheDirectory() -> URL {
        modelsRootDirectory()
            .appendingPathComponent("qwen3-asr-1.7b-coreml", isDirectory: true)
    }

    static func modelsExist(at directory: URL) -> Bool {
        let fileManager = FileManager.default
        return hasModel(named: encoderName, in: directory)
            && hasModel(named: decoderName, in: directory)
            && fileManager.fileExists(atPath: directory.appendingPathComponent(embeddingsFile).path)
            && fileManager.fileExists(atPath: directory.appendingPathComponent(vocabularyFile).path)
    }

    static func load(from directory: URL, computeUnits: MLComputeUnits = .all) async throws -> Qwen3ASR17BLoadedModels {
        let config = MLModelConfiguration()
        config.computeUnits = computeUnits

        let encoder = try await loadModel(named: encoderName, from: directory, configuration: config)
        let decoder = try await loadModel(named: decoderName, from: directory, configuration: config)
        let embeddings = try Qwen3ASR17BEmbeddingWeights(
            contentsOf: directory.appendingPathComponent(embeddingsFile)
        )
        let vocabulary = try loadVocabulary(from: directory)
        return Qwen3ASR17BLoadedModels(
            audioEncoder: encoder,
            decoderStateful: decoder,
            embeddingWeights: embeddings,
            vocabulary: vocabulary
        )
    }

    private static func modelsRootDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    private static func hasModel(named name: String, in directory: URL) -> Bool {
        let fileManager = FileManager.default
        return fileManager.fileExists(atPath: directory.appendingPathComponent("\(name).mlmodelc").path)
            || fileManager.fileExists(atPath: directory.appendingPathComponent("\(name).mlpackage").path)
    }

    private static func loadModel(
        named name: String,
        from directory: URL,
        configuration: MLModelConfiguration
    ) async throws -> MLModel {
        let compiledPath = directory.appendingPathComponent("\(name).mlmodelc")
        let packagePath = directory.appendingPathComponent("\(name).mlpackage")

        let modelURL: URL
        if FileManager.default.fileExists(atPath: compiledPath.path) {
            modelURL = compiledPath
        } else if FileManager.default.fileExists(atPath: packagePath.path) {
            qwen17Logger.info("Compiling \(name, privacy: .public).mlpackage")
            let compiledURL = try await MLModel.compileModel(at: packagePath)
            try? FileManager.default.removeItem(at: compiledPath)
            try FileManager.default.copyItem(at: compiledURL, to: compiledPath)
            try? FileManager.default.removeItem(at: compiledURL)
            modelURL = compiledPath
        } else {
            throw Qwen3ASR17BError.modelNotFound(name)
        }

        return try await MLModel.load(contentsOf: modelURL, configuration: configuration)
    }

    private static func loadVocabulary(from directory: URL) throws -> [Int: String] {
        let data = try Data(contentsOf: directory.appendingPathComponent(vocabularyFile))
        guard let stringToID = try JSONSerialization.jsonObject(with: data) as? [String: Int] else {
            throw Qwen3ASR17BError.invalidVocabulary
        }

        var idToString: [Int: String] = [:]
        idToString.reserveCapacity(stringToID.count)
        for (token, id) in stringToID {
            idToString[id] = token
        }
        return idToString
    }
}

struct Qwen3ASR17BLoadedModels: Sendable {
    let audioEncoder: MLModel
    let decoderStateful: MLModel
    let embeddingWeights: Qwen3ASR17BEmbeddingWeights
    let vocabulary: [Int: String]
}

actor Qwen3ASR17BCoreMLManager {
    private var models: Qwen3ASR17BLoadedModels?
    private let rope = Qwen3ASR17BRoPE()
    private let melExtractor = WhisperMelSpectrogram()

    func loadModels(from directory: URL, computeUnits: MLComputeUnits = .all) async throws {
        models = try await Qwen3ASR17BCoreMLModels.load(from: directory, computeUnits: computeUnits)
    }

    func transcribe(audioSamples: [Float], language: String? = nil, maxNewTokens: Int = 512) async throws -> String {
        let mel = melExtractor.compute(audio: audioSamples)
        guard !mel.isEmpty else {
            throw Qwen3ASR17BError.generationFailed("Audio too short to extract mel spectrogram")
        }
        return try transcribe(melSpectrogram: mel, language: language, maxNewTokens: maxNewTokens)
    }

    private func transcribe(melSpectrogram: [[Float]], language: String?, maxNewTokens: Int) throws -> String {
        guard let models else {
            throw Qwen3ASR17BError.generationFailed("Models not loaded")
        }

        let resolvedLanguage = language.flatMap(Qwen3AsrConfig.Language.init(from:))
        let audioFeatures = try encodeAudio(melSpectrogram: melSpectrogram, models: models)
        let promptTokens = buildPromptTokens(numAudioFrames: audioFeatures.count, language: resolvedLanguage)
        let initialEmbeddings = embedAndMerge(
            promptTokens: promptTokens,
            audioFeatures: audioFeatures,
            models: models
        )
        let generatedTokenIds = try generate(
            initialEmbeddings: initialEmbeddings,
            promptLength: promptTokens.count,
            maxNewTokens: maxNewTokens,
            models: models
        )
        return decodeTokens(generatedTokenIds, vocabulary: models.vocabulary)
    }

    private func encodeAudio(melSpectrogram: [[Float]], models: Qwen3ASR17BLoadedModels) throws -> [[Float]] {
        let numFrames = melSpectrogram.first?.count ?? 0
        var allFeatures: [[Float]] = []
        var offset = 0

        while offset < numFrames {
            let end = min(offset + Qwen3ASR17BConfig.melWindowSize, numFrames)
            let currentWindowSize = end - offset
            let melInput = try createMelInput(
                melSpectrogram: melSpectrogram,
                offset: offset,
                windowSize: currentWindowSize,
                padTo: Qwen3ASR17BConfig.melWindowSize
            )

            let prediction = try models.audioEncoder.prediction(from: melInput)
            guard let features = prediction.multiArray(named: "audio_features") else {
                throw Qwen3ASR17BError.encoderFailed("No audio feature output")
            }

            let outputFrames = currentWindowSize == Qwen3ASR17BConfig.melWindowSize
                ? Qwen3ASR17BConfig.outputFramesPerWindow
                : (currentWindowSize + Qwen3ASR17BConfig.convDownsampleFactor - 1) / Qwen3ASR17BConfig.convDownsampleFactor

            for frame in 0..<outputFrames {
                var vector = [Float](repeating: 0, count: Qwen3ASR17BConfig.encoderOutputDim)
                for dim in 0..<Qwen3ASR17BConfig.encoderOutputDim {
                    vector[dim] = features[frame * Qwen3ASR17BConfig.encoderOutputDim + dim].floatValue
                }
                allFeatures.append(vector)
            }

            offset += Qwen3ASR17BConfig.melWindowSize
        }

        return allFeatures
    }

    private func createMelInput(
        melSpectrogram: [[Float]],
        offset: Int,
        windowSize: Int,
        padTo: Int
    ) throws -> MLDictionaryFeatureProvider {
        let shape: [NSNumber] = [1, 1, NSNumber(value: Qwen3ASR17BConfig.numMelBins), NSNumber(value: padTo)]
        let array = try MLMultiArray(shape: shape, dataType: .float32)
        let ptr = array.dataPointer.bindMemory(to: Float.self, capacity: array.count)
        ptr.initialize(repeating: 0, count: array.count)

        for bin in 0..<Qwen3ASR17BConfig.numMelBins {
            for time in 0..<windowSize {
                let sourceIndex = offset + time
                if sourceIndex < melSpectrogram[bin].count {
                    ptr[bin * padTo + time] = melSpectrogram[bin][sourceIndex]
                }
            }
        }

        return try MLDictionaryFeatureProvider(dictionary: [
            "mel_input": MLFeatureValue(multiArray: array)
        ])
    }

    private static let taskTokens: [Qwen3AsrConfig.Language: [Int32]] = [
        .english: [3246, 56541, 279, 7461, 311, 6364, 1467, 13],
        .chinese: [3246, 56541, 279, 7461, 311, 8449, 1467, 13],
        .cantonese: [3246, 56541, 279, 7461, 311, 56782, 26730, 1467, 13],
        .japanese: [3246, 56541, 279, 7461, 311, 11411, 1467, 13],
        .korean: [3246, 56541, 279, 7461, 311, 15791, 1467, 13],
        .french: [3246, 56541, 279, 7461, 311, 8620, 1467, 13],
        .german: [3246, 56541, 279, 7461, 311, 6581, 1467, 13],
        .spanish: [3246, 56541, 279, 7461, 311, 14610, 1467, 13],
        .portuguese: [3246, 56541, 279, 7461, 311, 42322, 1467, 13],
        .italian: [3246, 56541, 279, 7461, 311, 15333, 1467, 13],
        .russian: [3246, 56541, 279, 7461, 311, 10479, 1467, 13],
        .arabic: [3246, 56541, 279, 7461, 311, 17900, 1467, 13],
        .hindi: [3246, 56541, 279, 7461, 311, 43083, 1467, 13],
        .thai: [3246, 56541, 279, 7461, 311, 40764, 1467, 13],
        .vietnamese: [3246, 56541, 279, 7461, 311, 48416, 1467, 13],
        .indonesian: [3246, 56541, 279, 7461, 311, 66986, 1467, 13],
        .malay: [3246, 56541, 279, 7461, 311, 80985, 1467, 13],
        .turkish: [3246, 56541, 279, 7461, 311, 38703, 1467, 13],
        .dutch: [3246, 56541, 279, 7461, 311, 19227, 1467, 13],
        .swedish: [3246, 56541, 279, 7461, 311, 54259, 1467, 13],
        .danish: [3246, 56541, 279, 7461, 311, 39093, 1467, 13],
        .finnish: [3246, 56541, 279, 7461, 311, 56391, 1467, 13],
        .polish: [3246, 56541, 279, 7461, 311, 34827, 1467, 13],
        .czech: [3246, 56541, 279, 7461, 311, 51728, 1467, 13],
        .greek: [3246, 56541, 279, 7461, 311, 18173, 1467, 13],
        .hungarian: [3246, 56541, 279, 7461, 311, 57751, 1467, 13],
        .romanian: [3246, 56541, 279, 7461, 311, 56949, 1467, 13],
        .persian: [3246, 56541, 279, 7461, 311, 59181, 1467, 13],
        .filipino: [3246, 56541, 279, 7461, 311, 66847, 1467, 13],
        .macedonian: [3246, 56541, 279, 7461, 311, 17067, 103881, 1467, 13],
    ]

    private func buildPromptTokens(numAudioFrames: Int, language: Qwen3AsrConfig.Language?) -> [Int32] {
        var tokens: [Int32] = []
        tokens.append(Int32(Qwen3ASR17BConfig.imStartTokenId))
        tokens.append(Int32(Qwen3ASR17BConfig.systemTokenId))
        tokens.append(Int32(Qwen3ASR17BConfig.newlineTokenId))
        if let language, let taskTokens = Self.taskTokens[language] {
            tokens.append(contentsOf: taskTokens)
        }
        tokens.append(Int32(Qwen3ASR17BConfig.imEndTokenId))
        tokens.append(Int32(Qwen3ASR17BConfig.newlineTokenId))

        tokens.append(Int32(Qwen3ASR17BConfig.imStartTokenId))
        tokens.append(Int32(Qwen3ASR17BConfig.userTokenId))
        tokens.append(Int32(Qwen3ASR17BConfig.newlineTokenId))
        tokens.append(Int32(Qwen3ASR17BConfig.audioStartTokenId))
        tokens.append(contentsOf: Array(repeating: Int32(Qwen3ASR17BConfig.audioTokenId), count: numAudioFrames))
        tokens.append(Int32(Qwen3ASR17BConfig.audioEndTokenId))
        tokens.append(Int32(Qwen3ASR17BConfig.imEndTokenId))
        tokens.append(Int32(Qwen3ASR17BConfig.newlineTokenId))

        tokens.append(Int32(Qwen3ASR17BConfig.imStartTokenId))
        tokens.append(Int32(Qwen3ASR17BConfig.assistantTokenId))
        tokens.append(Int32(Qwen3ASR17BConfig.newlineTokenId))
        return tokens
    }

    private func embedAndMerge(
        promptTokens: [Int32],
        audioFeatures: [[Float]],
        models: Qwen3ASR17BLoadedModels
    ) -> [[Float]] {
        var embeddings = models.embeddingWeights.embeddings(for: promptTokens)
        var audioIndex = 0
        for index in promptTokens.indices where promptTokens[index] == Int32(Qwen3ASR17BConfig.audioTokenId) {
            guard audioIndex < audioFeatures.count else { break }
            embeddings[index] = audioFeatures[audioIndex]
            audioIndex += 1
        }
        return embeddings
    }

    private func generate(
        initialEmbeddings: [[Float]],
        promptLength: Int,
        maxNewTokens: Int,
        models: Qwen3ASR17BLoadedModels
    ) throws -> [Int] {
        let state = models.decoderStateful.makeState()
        let effectiveMaxNew = min(maxNewTokens, Qwen3ASR17BConfig.maxCacheSeqLen - promptLength)
        guard effectiveMaxNew > 0 else {
            throw Qwen3ASR17BError.generationFailed(
                "Prompt length \(promptLength) exceeds cache capacity \(Qwen3ASR17BConfig.maxCacheSeqLen)"
            )
        }

        var generatedTokens: [Int] = []
        var currentPosition = promptLength
        let (prefillCos, prefillSin) = rope.computeRange(startPosition: 0, count: promptLength)
        let prefillLogits = try runStatefulDecoder(
            hiddenStates: createBatchedHiddenArray(embeddings: Array(initialEmbeddings[0..<promptLength])),
            positionCos: createBatchedPositionArray(values: prefillCos, seqLen: promptLength),
            positionSin: createBatchedPositionArray(values: prefillSin, seqLen: promptLength),
            mask: createPrefillMask(seqLen: promptLength),
            state: state,
            models: models
        )

        let firstTokenID = argmaxFromLogits(prefillLogits)
        if !Qwen3ASR17BConfig.eosTokenIds.contains(firstTokenID) {
            generatedTokens.append(firstTokenID)
        }
        if Qwen3ASR17BConfig.eosTokenIds.contains(firstTokenID) {
            return generatedTokens
        }

        let decodeHiddenArray = try MLMultiArray(
            shape: [1, 1, NSNumber(value: Qwen3ASR17BConfig.hiddenSize)],
            dataType: .float32
        )
        let decodeHiddenPtr = decodeHiddenArray.dataPointer.bindMemory(
            to: Float.self,
            capacity: Qwen3ASR17BConfig.hiddenSize
        )
        let decodeCosArray = try MLMultiArray(
            shape: [1, 1, NSNumber(value: Qwen3ASR17BConfig.headDim)],
            dataType: .float32
        )
        let decodeCosPtr = decodeCosArray.dataPointer.bindMemory(
            to: Float.self,
            capacity: Qwen3ASR17BConfig.headDim
        )
        let decodeSinArray = try MLMultiArray(
            shape: [1, 1, NSNumber(value: Qwen3ASR17BConfig.headDim)],
            dataType: .float32
        )
        let decodeSinPtr = decodeSinArray.dataPointer.bindMemory(
            to: Float.self,
            capacity: Qwen3ASR17BConfig.headDim
        )

        for _ in 1..<effectiveMaxNew {
            guard let lastTokenID = generatedTokens.last else { break }
            let nextEmbedding = models.embeddingWeights.embedding(for: lastTokenID)
            nextEmbedding.withUnsafeBufferPointer { source in
                _ = memcpy(
                    decodeHiddenPtr,
                    source.baseAddress!,
                    Qwen3ASR17BConfig.hiddenSize * MemoryLayout<Float>.size
                )
            }
            rope.fill(position: currentPosition, cosPtr: decodeCosPtr, sinPtr: decodeSinPtr)
            let logits = try runStatefulDecoder(
                hiddenStates: decodeHiddenArray,
                positionCos: decodeCosArray,
                positionSin: decodeSinArray,
                mask: createDecodeMask(endStep: currentPosition + 1),
                state: state,
                models: models
            )
            currentPosition += 1

            let tokenID = argmaxFromLogits(logits)
            if Qwen3ASR17BConfig.eosTokenIds.contains(tokenID) {
                break
            }
            generatedTokens.append(tokenID)
        }

        return generatedTokens
    }

    private func runStatefulDecoder(
        hiddenStates: MLMultiArray,
        positionCos: MLMultiArray,
        positionSin: MLMultiArray,
        mask: MLMultiArray,
        state: MLState,
        models: Qwen3ASR17BLoadedModels
    ) throws -> MLMultiArray {
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "hidden_states": MLFeatureValue(multiArray: hiddenStates),
            "position_cos": MLFeatureValue(multiArray: positionCos),
            "position_sin": MLFeatureValue(multiArray: positionSin),
            "attention_mask": MLFeatureValue(multiArray: mask),
        ])
        let output = try models.decoderStateful.prediction(from: input, using: state)
        guard let logits = output.multiArray(named: "logits") else {
            throw Qwen3ASR17BError.decoderFailed("Missing logits output")
        }
        return logits
    }

    private func argmaxFromLogits(_ logits: MLMultiArray) -> Int {
        let ptr = logits.dataPointer.bindMemory(to: Float.self, capacity: Qwen3ASR17BConfig.vocabSize)
        var maxValue: Float = 0
        var maxIndex: vDSP_Length = 0
        vDSP_maxvi(ptr, 1, &maxValue, &maxIndex, vDSP_Length(Qwen3ASR17BConfig.vocabSize))
        return Int(maxIndex)
    }

    private static let bpeUnicodeToByte: [UInt32: UInt8] = {
        var printable = [Int]()
        printable.append(contentsOf: 33...126)
        printable.append(contentsOf: 161...172)
        printable.append(contentsOf: 174...255)
        let printableSet = Set(printable)

        var mapping = [UInt32: UInt8]()
        for byte in printable {
            mapping[UInt32(byte)] = UInt8(byte)
        }
        var extra: UInt32 = 256
        for byte in 0...255 where !printableSet.contains(byte) {
            mapping[extra] = UInt8(byte)
            extra += 1
        }
        return mapping
    }()

    private func decodeTokens(_ tokenIds: [Int], vocabulary: [Int: String]) -> String {
        let startIndex = tokenIds.firstIndex(of: Qwen3ASR17BConfig.asrTextTokenId).map { $0 + 1 } ?? 0
        let pieces = tokenIds[startIndex...].compactMap { vocabulary[$0] }.joined()

        var bytes: [UInt8] = []
        for scalar in pieces.unicodeScalars {
            if let byte = Self.bpeUnicodeToByte[scalar.value] {
                bytes.append(byte)
            }
        }
        let decoded = String(bytes: bytes, encoding: .utf8) ?? String(pieces.filter(\.isASCII))
        return decoded.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func createPrefillMask(seqLen: Int) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: [1, 1, NSNumber(value: seqLen), NSNumber(value: seqLen)], dataType: .float32)
        let ptr = array.dataPointer.bindMemory(to: Float.self, capacity: seqLen * seqLen)
        for row in 0..<seqLen {
            for column in 0..<seqLen {
                ptr[row * seqLen + column] = column > row ? Float(-1e9) : 0
            }
        }
        return array
    }

    private func createDecodeMask(endStep: Int) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: [1, 1, 1, NSNumber(value: endStep)], dataType: .float32)
        let ptr = array.dataPointer.bindMemory(to: Float.self, capacity: endStep)
        ptr.initialize(repeating: 0, count: endStep)
        return array
    }

    private func createBatchedHiddenArray(embeddings: [[Float]]) throws -> MLMultiArray {
        let seqLen = embeddings.count
        let array = try MLMultiArray(
            shape: [1, NSNumber(value: seqLen), NSNumber(value: Qwen3ASR17BConfig.hiddenSize)],
            dataType: .float32
        )
        let ptr = array.dataPointer.bindMemory(
            to: Float.self,
            capacity: seqLen * Qwen3ASR17BConfig.hiddenSize
        )
        for index in 0..<seqLen {
            let offset = index * Qwen3ASR17BConfig.hiddenSize
            for dim in 0..<Qwen3ASR17BConfig.hiddenSize {
                ptr[offset + dim] = embeddings[index][dim]
            }
        }
        return array
    }

    private func createBatchedPositionArray(values: [Float], seqLen: Int) throws -> MLMultiArray {
        let array = try MLMultiArray(
            shape: [1, NSNumber(value: seqLen), NSNumber(value: Qwen3ASR17BConfig.headDim)],
            dataType: .float32
        )
        let ptr = array.dataPointer.bindMemory(to: Float.self, capacity: values.count)
        for index in values.indices {
            ptr[index] = values[index]
        }
        return array
    }
}

private enum Qwen3ASR17BConfig {
    static let sampleRate = 16000
    static let numMelBins = 128
    static let melWindowSize = 100
    static let convDownsampleFactor = 8
    static let outputFramesPerWindow = (melWindowSize + convDownsampleFactor - 1) / convDownsampleFactor
    static let encoderOutputDim = 2048
    static let hiddenSize = 2048
    static let headDim = 128
    static let vocabSize = 151_936
    static let ropeTheta: Double = 1_000_000
    static let audioStartTokenId = 151_669
    static let audioEndTokenId = 151_670
    static let audioTokenId = 151_676
    static let asrTextTokenId = 151_704
    static let eosTokenIds: Set<Int> = [151_645, 151_643]
    static let imStartTokenId = 151_644
    static let imEndTokenId = 151_645
    static let systemTokenId = 8948
    static let userTokenId = 872
    static let assistantTokenId = 77_091
    static let newlineTokenId = 198
    static let maxCacheSeqLen = 512
}

private struct Qwen3ASR17BRoPE: Sendable {
    private let invFreq: [Float]
    private let cosTable: [Float]
    private let sinTable: [Float]

    init() {
        let theta = Float(Qwen3ASR17BConfig.ropeTheta)
        let dim = Float(Qwen3ASR17BConfig.headDim)
        var frequencies = [Float](repeating: 0, count: Qwen3ASR17BConfig.headDim / 2)
        for index in stride(from: 0, to: Qwen3ASR17BConfig.headDim, by: 2) {
            frequencies[index / 2] = 1 / powf(theta, Float(index) / dim)
        }
        invFreq = frequencies

        let halfDim = Qwen3ASR17BConfig.headDim / 2
        var cos = [Float](repeating: 0, count: Qwen3ASR17BConfig.maxCacheSeqLen * Qwen3ASR17BConfig.headDim)
        var sin = cos
        for position in 0..<Qwen3ASR17BConfig.maxCacheSeqLen {
            let offset = position * Qwen3ASR17BConfig.headDim
            for index in 0..<halfDim {
                let angle = Float(position) * frequencies[index]
                let c = cosf(angle)
                let s = sinf(angle)
                cos[offset + index] = c
                cos[offset + index + halfDim] = c
                sin[offset + index] = s
                sin[offset + index + halfDim] = s
            }
        }
        cosTable = cos
        sinTable = sin
    }

    func fill(position: Int, cosPtr: UnsafeMutablePointer<Float>, sinPtr: UnsafeMutablePointer<Float>) {
        let values = compute(position: position)
        values.cos.withUnsafeBufferPointer { source in
            _ = memcpy(cosPtr, source.baseAddress!, Qwen3ASR17BConfig.headDim * MemoryLayout<Float>.stride)
        }
        values.sin.withUnsafeBufferPointer { source in
            _ = memcpy(sinPtr, source.baseAddress!, Qwen3ASR17BConfig.headDim * MemoryLayout<Float>.stride)
        }
    }

    func computeRange(startPosition: Int, count: Int) -> (cos: [Float], sin: [Float]) {
        let endPosition = startPosition + count
        guard endPosition <= Qwen3ASR17BConfig.maxCacheSeqLen else {
            return computeRangeDynamic(startPosition: startPosition, count: count)
        }
        let startOffset = startPosition * Qwen3ASR17BConfig.headDim
        let endOffset = endPosition * Qwen3ASR17BConfig.headDim
        return (
            cos: Array(cosTable[startOffset..<endOffset]),
            sin: Array(sinTable[startOffset..<endOffset])
        )
    }

    private func compute(position: Int) -> (cos: [Float], sin: [Float]) {
        guard position < Qwen3ASR17BConfig.maxCacheSeqLen else {
            return computeRangeDynamic(startPosition: position, count: 1)
        }
        let offset = position * Qwen3ASR17BConfig.headDim
        return (
            cos: Array(cosTable[offset..<(offset + Qwen3ASR17BConfig.headDim)]),
            sin: Array(sinTable[offset..<(offset + Qwen3ASR17BConfig.headDim)])
        )
    }

    private func computeRangeDynamic(startPosition: Int, count: Int) -> (cos: [Float], sin: [Float]) {
        let halfDim = Qwen3ASR17BConfig.headDim / 2
        var cosValues = [Float](repeating: 0, count: count * Qwen3ASR17BConfig.headDim)
        var sinValues = cosValues
        for positionOffset in 0..<count {
            let position = Float(startPosition + positionOffset)
            let offset = positionOffset * Qwen3ASR17BConfig.headDim
            for index in 0..<halfDim {
                let angle = position * invFreq[index]
                let c = cosf(angle)
                let s = sinf(angle)
                cosValues[offset + index] = c
                cosValues[offset + index + halfDim] = c
                sinValues[offset + index] = s
                sinValues[offset + index + halfDim] = s
            }
        }
        return (cosValues, sinValues)
    }
}

final class Qwen3ASR17BEmbeddingWeights: @unchecked Sendable {
    let vocabSize: Int
    let hiddenSize: Int
    private let data: Data

    init(contentsOf url: URL) throws {
        let fileData = try Data(contentsOf: url)
        guard fileData.count >= 8 else {
            throw Qwen3ASR17BError.invalidVocabulary
        }

        vocabSize = Int(fileData.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self) })
        hiddenSize = Int(fileData.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) })
        guard vocabSize == Qwen3ASR17BConfig.vocabSize else {
            throw Qwen3ASR17BError.generationFailed("Embedding vocab size \(vocabSize) is not \(Qwen3ASR17BConfig.vocabSize)")
        }
        guard hiddenSize == Qwen3ASR17BConfig.hiddenSize else {
            throw Qwen3ASR17BError.generationFailed("Embedding hidden size \(hiddenSize) is not \(Qwen3ASR17BConfig.hiddenSize)")
        }
        let expectedSize = 8 + vocabSize * hiddenSize * 2
        guard fileData.count == expectedSize else {
            throw Qwen3ASR17BError.generationFailed("Embedding file size mismatch: expected \(expectedSize), got \(fileData.count)")
        }
        data = fileData
    }

    func embedding(for tokenID: Int) -> [Float] {
        guard tokenID >= 0, tokenID < vocabSize else {
            return [Float](repeating: 0, count: hiddenSize)
        }
        let offset = 8 + tokenID * hiddenSize * 2
        var result = [Float](repeating: 0, count: hiddenSize)
        #if arch(arm64)
        data.withUnsafeBytes { pointer in
            let float16Pointer = pointer.baseAddress!.advanced(by: offset).assumingMemoryBound(to: Float16.self)
            for index in 0..<hiddenSize {
                result[index] = Float(float16Pointer[index])
            }
        }
        #endif
        return result
    }

    func embeddings(for tokenIDs: [Int32]) -> [[Float]] {
        tokenIDs.map { embedding(for: Int($0)) }
    }
}

private enum Qwen3ASR17BError: LocalizedError {
    case modelNotFound(String)
    case invalidVocabulary
    case encoderFailed(String)
    case decoderFailed(String)
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case let .modelNotFound(name):
            return "Qwen3-ASR-1.7B model not found: \(name)"
        case .invalidVocabulary:
            return "Invalid Qwen3-ASR-1.7B vocabulary file."
        case let .encoderFailed(message):
            return "Qwen3-ASR-1.7B encoder failed: \(message)"
        case let .decoderFailed(message):
            return "Qwen3-ASR-1.7B decoder failed: \(message)"
        case let .generationFailed(message):
            return "Qwen3-ASR-1.7B generation failed: \(message)"
        }
    }
}

private extension MLFeatureProvider {
    func multiArray(named preferredName: String) -> MLMultiArray? {
        if let value = featureValue(for: preferredName)?.multiArrayValue {
            return value
        }
        for name in featureNames {
            if let value = featureValue(for: name)?.multiArrayValue {
                return value
            }
        }
        return nil
    }
}
