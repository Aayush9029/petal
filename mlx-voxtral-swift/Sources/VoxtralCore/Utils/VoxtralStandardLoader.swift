/**
 * VoxtralStandardLoader - Standard MLX Swift approach (no wrapper)
 * 
 * This implements the standard MLX Swift pattern observed in all successful projects:
 * 1. Configuration → 2. Direct Model Creation → 3. MLXLMCommon.loadWeights
 * 
 * This approach follows exactly the same patterns as:
 * - MLXLLM/LlamaModel.swift
 * - MLXVLM/PaliGemmaModel.swift  
 * - All other MLX Swift examples
 */

import Foundation
import MLX
import MLXNN
import MLXLMCommon

/**
 * Standard MLX Swift Configuration Pattern
 * Follows Codable pattern used by all MLX Swift projects
 * Swift 6: Sendable because all properties are immutable Codable values
 */
public struct VoxtralStandardConfiguration: Codable, Sendable {
    public let modelType: String
    public let textConfig: TextConfiguration
    public let audioConfig: AudioConfiguration
    public let audioTokenId: Int
    public let projectorHiddenAct: String
    public let quantization: [String: QuantizationValue]?
    
    public struct TextConfiguration: Codable, Sendable {
        public let vocabularySize: Int
        public let hiddenSize: Int
        public let intermediateSize: Int
        public let hiddenLayers: Int
        public let attentionHeads: Int
        public let kvHeads: Int
        public let headDim: Int?
        public let maxPositionEmbeddings: Int
        public let rmsNormEps: Float
        public let ropeTheta: Float
        public let hiddenAct: String
        public let attentionBias: Bool
        public let mlpBias: Bool
        
        enum CodingKeys: String, CodingKey {
            case vocabularySize = "vocab_size"
            case hiddenSize = "hidden_size"
            case intermediateSize = "intermediate_size"
            case hiddenLayers = "num_hidden_layers"
            case attentionHeads = "num_attention_heads"
            case kvHeads = "num_key_value_heads"
            case headDim = "head_dim"
            case maxPositionEmbeddings = "max_position_embeddings"
            case rmsNormEps = "rms_norm_eps"
            case ropeTheta = "rope_theta"
            case hiddenAct = "hidden_act"
            case attentionBias = "attention_bias"
            case mlpBias = "mlp_bias"
        }
    }
    
    public struct AudioConfiguration: Codable, Sendable {
        public let hiddenSize: Int
        public let intermediateSize: Int
        public let hiddenLayers: Int
        public let attentionHeads: Int
        public let kvHeads: Int
        public let headDim: Int
        public let maxSourcePositions: Int
        public let numMelBins: Int
        public let vocabularySize: Int
        
        enum CodingKeys: String, CodingKey {
            case hiddenSize = "hidden_size"
            case intermediateSize = "intermediate_size"
            case hiddenLayers = "num_hidden_layers"
            case attentionHeads = "num_attention_heads"
            case kvHeads = "num_key_value_heads"
            case headDim = "head_dim"
            case maxSourcePositions = "max_source_positions"
            case numMelBins = "num_mel_bins"
            case vocabularySize = "vocab_size"
        }
    }
    
    public enum QuantizationValue: Codable, Sendable {
        case bool(Bool)
        case int(Int)
        case config(QuantizationConfig)

        public struct QuantizationConfig: Codable, Sendable {
            public let groupSize: Int
            public let bits: Int

            enum CodingKeys: String, CodingKey {
                case groupSize = "group_size"
                case bits
            }
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()

            if let boolValue = try? container.decode(Bool.self) {
                self = .bool(boolValue)
            } else if let intValue = try? container.decode(Int.self) {
                self = .int(intValue)
            } else if let configValue = try? container.decode(QuantizationConfig.self) {
                self = .config(configValue)
            } else {
                throw DecodingError.typeMismatch(QuantizationValue.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected Bool, Int or QuantizationConfig"))
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()

            switch self {
            case .bool(let value):
                try container.encode(value)
            case .int(let value):
                try container.encode(value)
            case .config(let config):
                try container.encode(config)
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case modelType = "model_type"
        case textConfig = "text_config"
        case audioConfig = "audio_config"
        case audioTokenId = "audio_token_id"
        case projectorHiddenAct = "projector_hidden_act"
        case quantization
    }
}

/**
 * LlamaStandardConfig - Configuration for migrated Llama components
 * Compatible with both new config structure and legacy parameters
 */
public struct LlamaStandardConfig {
    public let vocabSize: Int  // ✅ AJOUTÉ: vocab_size manquant !
    public let hiddenSize: Int
    public let intermediateSize: Int
    public let numHiddenLayers: Int
    public let numAttentionHeads: Int
    public let numKeyValueHeads: Int
    public let headDim: Int
    public let maxPositionEmbeddings: Int
    public let rmsNormEps: Float
    public let ropeTheta: Float
    public let attentionBias: Bool
    public let mlpBias: Bool

    public init(
        vocabSize: Int = 131072,  // ✅ AJOUTÉ avec default Voxtral
        hiddenSize: Int,
        intermediateSize: Int = 11008,
        numHiddenLayers: Int = 32,
        numAttentionHeads: Int = 32,
        numKeyValueHeads: Int = 32,
        headDim: Int = 128,
        maxPositionEmbeddings: Int = 32768,
        rmsNormEps: Float = 1e-5,
        ropeTheta: Float = 10000.0,
        attentionBias: Bool = false,
        mlpBias: Bool = false
    ) {
        self.vocabSize = vocabSize  // ✅ AJOUTÉ
        self.hiddenSize = hiddenSize
        self.intermediateSize = intermediateSize
        self.numHiddenLayers = numHiddenLayers
        self.numAttentionHeads = numAttentionHeads
        self.numKeyValueHeads = numKeyValueHeads
        self.headDim = headDim
        self.maxPositionEmbeddings = maxPositionEmbeddings
        self.rmsNormEps = rmsNormEps
        self.ropeTheta = ropeTheta
        self.attentionBias = attentionBias
        self.mlpBias = mlpBias
    }

    // Convenience initializer from VoxtralStandardConfiguration
    public init(from config: VoxtralStandardConfiguration) {
        self.vocabSize = config.textConfig.vocabularySize  // ✅ CORRIGÉ: utilise la vraie vocab_size !
        self.hiddenSize = config.textConfig.hiddenSize
        self.intermediateSize = config.textConfig.intermediateSize
        self.numHiddenLayers = config.textConfig.hiddenLayers
        self.numAttentionHeads = config.textConfig.attentionHeads
        self.numKeyValueHeads = config.textConfig.kvHeads
        self.headDim = config.textConfig.headDim ?? 128
        self.maxPositionEmbeddings = config.textConfig.maxPositionEmbeddings
        self.rmsNormEps = config.textConfig.rmsNormEps
        self.ropeTheta = config.textConfig.ropeTheta
        self.attentionBias = config.textConfig.attentionBias
        self.mlpBias = config.textConfig.mlpBias
    }
}

/**
 * Standard MLX Swift Model Implementation - Direct Approach
 * NO @ModuleInfo wrappers, NO dimension detection - just like all other MLX Swift projects
 */
// Container to match language_model.* parameter names
public class LanguageModelContainer: Module {
    @ModuleInfo var lmHead: Linear
    @ModuleInfo var model: LlamaStandardModel
    
    public init(configuration: VoxtralStandardConfiguration) {
        self.lmHead = Linear(
            configuration.textConfig.hiddenSize,
            configuration.textConfig.vocabularySize,
            bias: false
        )
        
        // Use the corrected constructor with LlamaStandardConfig
        let llamaConfig = LlamaStandardConfig(
            vocabSize: configuration.textConfig.vocabularySize,
            hiddenSize: configuration.textConfig.hiddenSize,
            intermediateSize: configuration.textConfig.intermediateSize,
            numHiddenLayers: configuration.textConfig.hiddenLayers,
            numAttentionHeads: configuration.textConfig.attentionHeads,
            numKeyValueHeads: configuration.textConfig.kvHeads,
            headDim: configuration.textConfig.headDim ?? 128,
            maxPositionEmbeddings: configuration.textConfig.maxPositionEmbeddings,
            rmsNormEps: configuration.textConfig.rmsNormEps,
            ropeTheta: configuration.textConfig.ropeTheta,
            attentionBias: configuration.textConfig.attentionBias,
            mlpBias: configuration.textConfig.mlpBias
        )

        self.model = LlamaStandardModel(config: llamaConfig)
        
        super.init()
    }
}

/// Swift 6: @unchecked Sendable for ML models - caller ensures single-threaded access
public class VoxtralStandardModel: Module, LanguageModel, KVCacheDimensionProvider, @unchecked Sendable {
    // Structure matching real parameter names in safetensors
    public let languageModel: LanguageModelContainer
    public let audioTower: VoxtralStandardEncoder
    public let multiModalProjector: VoxtralStandardProjector

    let configuration: VoxtralStandardConfiguration
    // MARK: - LanguageModel Protocol Implementation
    public var vocabularySize: Int { configuration.textConfig.vocabularySize }

    public func prepare(
        _ input: LMInput, cache: [any KVCache], state: LMOutput.State?, prefill: PrefillParameters
    ) throws -> PrepareResult {
        // Simple implementation for testing - just return tokens to evaluate
        return .tokens(input.text)
    }

    // KVCacheDimensionProvider protocol for automatic newCache implementation
    public var kvHeads: [Int] {
        // Return number of kv heads for each layer
        return Array(repeating: configuration.textConfig.kvHeads, count: configuration.textConfig.hiddenLayers)
    }

    public var headDim: Int {
        return configuration.textConfig.headDim ?? 128
    }
    public init(configuration: VoxtralStandardConfiguration) {
        self.configuration = configuration
        
        VoxtralDebug.log("Creating VoxtralStandardModel")
        
        // Create language model container - matches language_model.* parameter names
        self.languageModel = LanguageModelContainer(configuration: configuration)
        
        // Create audio tower
        self.audioTower = VoxtralStandardEncoder(
            hiddenSize: configuration.audioConfig.hiddenSize,
            intermediateSize: configuration.audioConfig.intermediateSize,
            hiddenLayers: configuration.audioConfig.hiddenLayers,
            attentionHeads: configuration.audioConfig.attentionHeads,
            kvHeads: configuration.audioConfig.kvHeads,
            headDim: configuration.audioConfig.headDim,
            maxSourcePositions: configuration.audioConfig.maxSourcePositions,
            numMelBins: configuration.audioConfig.numMelBins
        )
        
        // Create multi-modal projector with VOXTRAL SPECIFIC dimensions
        // CRITICAL: input is audio intermediate_size (5120), not hidden_size (1280)!
        self.multiModalProjector = VoxtralStandardProjector(
            inputSize: configuration.audioConfig.intermediateSize,  // 5120 - VOXTRAL SPECIFIC!
            hiddenSize: configuration.textConfig.hiddenSize,        // 3072
            hiddenAct: configuration.projectorHiddenAct
        )
        
        super.init()
    }
    
    // LLMModel protocol: callAsFunction for generation
    public func callAsFunction(_ inputs: MLXArray, cache: [any KVCache]?) -> MLXArray {
        // Standard MLX Swift pattern: forward pass through language model then lm_head
        let hiddenStates = languageModel.model(inputs, cache: cache)
        return languageModel.lmHead(hiddenStates)
    }

}

/**
 * Simplified Llama Model - Standard MLX Swift Pattern
 */
public class LlamaStandardModel: Module {
    let config: LlamaStandardConfig
    let paddingIdx: Int?
    let vocabSize: Int
    @ModuleInfo var embedTokens: Embedding
    @ModuleInfo var layers: [LlamaStandardBlock]
    @ModuleInfo var norm: RMSNorm

    /**
     * Direct Python equivalent: def __init__(self, config):
     */
    public init(config: LlamaStandardConfig) {
        // Python: self.config = config
        self.config = config
        // Python: self.padding_idx = getattr(config, "pad_token_id", None)
        self.paddingIdx = nil  // Will be added when needed
        // Python: self.vocab_size = config.vocab_size
        self.vocabSize = config.vocabSize  // ✅ CORRIGÉ: utilise config.vocabSize (131072)

        // Python: self.embed_tokens = nn.Embedding(config.vocab_size, config.hidden_size)
        self._embedTokens.wrappedValue = Embedding(embeddingCount: config.vocabSize, dimensions: config.hiddenSize)  // ✅ CORRIGÉ: 131072x3072!

        // Python: self.layers = [LlamaDecoderLayer(config) for _ in range(config.num_hidden_layers)]
        self._layers.wrappedValue = (0..<config.numHiddenLayers).map { _ in
            LlamaStandardBlock(config: config)
        }

        // Python: self.norm = nn.RMSNorm(config.hidden_size, eps=config.rms_norm_eps)
        self._norm.wrappedValue = RMSNorm(dimensions: config.hiddenSize, eps: config.rmsNormEps)

        super.init()
    }

    // Legacy constructor for backward compatibility
    public init(vocabularySize: Int, hiddenSize: Int, intermediateSize: Int,
                hiddenLayers: Int, attentionHeads: Int, kvHeads: Int, headDim: Int,
                maxPositionEmbeddings: Int, rmsNormEps: Float, ropeTheta: Float,
                hiddenAct: String, attentionBias: Bool, mlpBias: Bool) {

        let config = LlamaStandardConfig(
            vocabSize: vocabularySize,  // ✅ CRITIQUE: passer la vraie vocabularySize !
            hiddenSize: hiddenSize,
            intermediateSize: intermediateSize,
            numHiddenLayers: hiddenLayers,
            numAttentionHeads: attentionHeads,
            numKeyValueHeads: kvHeads,
            headDim: headDim,
            maxPositionEmbeddings: maxPositionEmbeddings,
            rmsNormEps: rmsNormEps,
            ropeTheta: ropeTheta,
            attentionBias: attentionBias,
            mlpBias: mlpBias
        )

        self.config = config
        self.paddingIdx = nil
        self.vocabSize = vocabularySize

        self._embedTokens.wrappedValue = Embedding(embeddingCount: vocabularySize, dimensions: hiddenSize)

        self._layers.wrappedValue = (0..<hiddenLayers).map { _ in
            LlamaStandardBlock(config: config)
        }

        self._norm.wrappedValue = RMSNorm(dimensions: hiddenSize, eps: rmsNormEps)

        super.init()
    }
    
    /**
     * Direct Python equivalent: def __call__(self, inputs: Optional[mx.array] = None, mask: Optional[mx.array] = None, cache: Optional[List[KVCache]] = None, inputs_embeds: Optional[mx.array] = None) -> mx.array:
     */
    public func callAsFunction(
        inputs: MLXArray? = nil,
        mask: MLXArray? = nil,
        cache: [any KVCache]? = nil,
        inputsEmbeds: MLXArray? = nil
    ) -> MLXArray {
        var hiddenStates: MLXArray

        // Python: if inputs_embeds is not None:
        if let inputsEmbeds = inputsEmbeds {
            // Python: h = inputs_embeds
            hiddenStates = inputsEmbeds
        } else {
            // Python: h = self.embed_tokens(inputs)
            hiddenStates = embedTokens(inputs!)
        }

        var attentionMask = mask
        // Python: if mask is None:
        if attentionMask == nil {
            // Python: mask = create_attention_mask(h, cache)
            // For now, MLX Swift handles this internally, but we could implement createAttentionMask
            // createAttentionMask creates a causal mask based on sequence length
            attentionMask = createCausalAttentionMask(hiddenStates: hiddenStates, cache: cache)
        }

        var layerCaches: [(any KVCache)?]
        // Python: if cache is None:
        if let cache = cache {
            layerCaches = cache.map { $0 as (any KVCache)? }
        } else {
            // Python: cache = [None] * len(self.layers)
            layerCaches = Array<(any KVCache)?>(repeating: nil, count: layers.count)
        }

        // Python: for layer, c in zip(self.layers, cache):
        for (layer, layerCache) in zip(layers, layerCaches) {
            // Python: h = layer(h, mask, cache=c)
            hiddenStates = layer.callAsFunction(hiddenStates, attentionMask: attentionMask, cache: layerCache)
        }

        // Python: return self.norm(h)
        return norm(hiddenStates)
    }

    // Legacy backward compatibility callAsFunction
    public func callAsFunction(_ inputs: MLXArray, cache: [any KVCache]?) -> MLXArray {
        return callAsFunction(inputs: inputs, mask: nil, cache: cache, inputsEmbeds: nil)
    }

    /**
     * Create causal attention mask for Llama model
     * This is equivalent to MLX-LM's create_attention_mask function
     *
     * Python reference from mlx_lm/models/base.py:
     *   if T > 1:
     *       if return_array:
     *           return create_causal_mask(T, offset, window_size=window_size)
     *       else:
     *           return "causal"
     *   else:
     *       mask = None
     *
     * MLX Swift's scaledDotProductAttention expects an additive mask:
     * - 0 where attention is allowed
     * - -inf (or large negative) where attention should be blocked
     */
    private func createCausalAttentionMask(hiddenStates: MLXArray, cache: [any KVCache]?) -> MLXArray? {
        let T = hiddenStates.shape[1]  // Sequence length

        // Python: if T > 1 -> return "causal" (or causal mask array)
        // For single token (T == 1), return nil (no mask needed)
        if T <= 1 {
            return nil
        }

        // Get offset from cache if available
        let offset = cache?.first?.offset ?? 0

        // Total sequence length including cached positions
        let totalLen = T + offset

        // Create indices for comparison
        // Row indices for queries (the new tokens at positions offset..offset+T)
        // Col indices for keys (all positions 0..totalLen)
        let rowIndices = MLXArray((offset..<(offset+T)).map { Float($0) }).reshaped([T, 1])
        let colIndices = MLXArray((0..<totalLen).map { Float($0) }).reshaped([1, totalLen])

        // Causal mask: block positions where col > row (future positions)
        // MLX expects additive mask: 0 for allowed, -inf for blocked
        let futureMask = colIndices .> rowIndices  // True where col > row

        // Convert boolean mask to additive mask: True -> -inf, False -> 0
        let minusInf = MLXArray(-Float.infinity)
        let zero = MLXArray(Float(0))
        let additiveMask = MLX.where(futureMask, minusInf, zero)

        return additiveMask
    }
}

/**
 * Direct Python equivalent: class LlamaDecoderLayer(nn.Module)
 * Llama decoder layer - exact migration from VoxtralLlama.swift
 * Uses @ModuleInfo for quantization support
 */
public class LlamaStandardBlock: Module {
    let hiddenSize: Int
    @ModuleInfo var selfAttn: LlamaStandardAttention
    @ModuleInfo var mlp: LlamaStandardMLP
    @ModuleInfo var inputLayerNorm: RMSNorm
    @ModuleInfo var postAttentionLayerNorm: RMSNorm

    /**
     * Direct Python equivalent: def __init__(self, config):
     */
    public init(config: LlamaStandardConfig) {
        // Python: self.hidden_size = config.hidden_size
        self.hiddenSize = config.hiddenSize

        // Python: self.self_attn = LlamaAttention(config)
        self._selfAttn.wrappedValue = LlamaStandardAttention(config: config)
        // Python: self.mlp = LlamaMLP(config)
        self._mlp.wrappedValue = LlamaStandardMLP(config: config)
        // Python: self.input_layernorm = nn.RMSNorm(config.hidden_size, eps=config.rms_norm_eps)
        self._inputLayerNorm.wrappedValue = RMSNorm(dimensions: config.hiddenSize, eps: config.rmsNormEps)
        // Python: self.post_attention_layernorm = nn.RMSNorm(config.hidden_size, eps=config.rms_norm_eps)
        self._postAttentionLayerNorm.wrappedValue = RMSNorm(dimensions: config.hiddenSize, eps: config.rmsNormEps)

        super.init()
    }

    // Legacy constructor for backward compatibility
    public init(hiddenSize: Int, intermediateSize: Int, attentionHeads: Int,
                kvHeads: Int, headDim: Int, maxPositionEmbeddings: Int, rmsNormEps: Float, ropeTheta: Float,
                attentionBias: Bool, mlpBias: Bool) {
        let config = LlamaStandardConfig(
            hiddenSize: hiddenSize,
            intermediateSize: intermediateSize,
            numAttentionHeads: attentionHeads,
            numKeyValueHeads: kvHeads,
            headDim: headDim,
            maxPositionEmbeddings: maxPositionEmbeddings,
            rmsNormEps: rmsNormEps,
            ropeTheta: ropeTheta,
            attentionBias: attentionBias,
            mlpBias: mlpBias
        )

        self.hiddenSize = hiddenSize
        self._selfAttn.wrappedValue = LlamaStandardAttention(config: config)
        self._mlp.wrappedValue = LlamaStandardMLP(config: config)
        self._inputLayerNorm.wrappedValue = RMSNorm(dimensions: hiddenSize, eps: rmsNormEps)
        self._postAttentionLayerNorm.wrappedValue = RMSNorm(dimensions: hiddenSize, eps: rmsNormEps)

        super.init()
    }

    /**
     * Direct Python equivalent: def __call__(self, hidden_states: mx.array, attention_mask: Optional[mx.array] = None, cache: Optional[KVCache] = None) -> mx.array:
     */
    public func callAsFunction(
        _ hiddenStates: MLXArray,
        attentionMask: MLXArray? = nil,
        cache: (any KVCache)? = nil
    ) -> MLXArray {
        // Python: r = self.self_attn(self.input_layernorm(hidden_states), attention_mask, cache)
        let r = selfAttn(inputLayerNorm(hiddenStates), attentionMask: attentionMask, cache: cache)
        // Python: h = hidden_states + r
        let h = hiddenStates + r
        // Python: r = self.mlp(self.post_attention_layernorm(h))
        let r2 = mlp(postAttentionLayerNorm(h))
        // Python: out = h + r
        let out = h + r2
        // Python: return out
        return out
    }

    // Overload for backward compatibility (cache only)
    public func callAsFunction(_ hiddenStates: MLXArray, cache: (any KVCache)?) -> MLXArray {
        return callAsFunction(hiddenStates, attentionMask: nil, cache: cache)
    }
}

/**
 * Complete Attention implementation - migrated from VoxtralLlama.swift
 * Direct Python equivalent: class LlamaAttention(nn.Module)
 * Uses @ModuleInfo for quantization support
 */
public class LlamaStandardAttention: Module {
    @ModuleInfo var qProj: Linear
    @ModuleInfo var kProj: Linear
    @ModuleInfo var vProj: Linear
    @ModuleInfo var oProj: Linear
    let rope: RoPE

    let headDim: Int
    let numHeads: Int
    let numKvHeads: Int
    let numKeyValueGroups: Int
    let maxPositionEmbeddings: Int
    let ropeTheta: Float
    let scale: Float

    /**
     * Direct Python equivalent: def __init__(self, config):
     */
    public init(config: LlamaStandardConfig) {
        // Python: self.head_dim = config.head_dim if hasattr(config, "head_dim") else (self.hidden_size // self.num_heads)
        self.headDim = config.headDim
        // Python: self.num_heads = config.num_attention_heads
        self.numHeads = config.numAttentionHeads
        // Python: self.num_key_value_heads = config.num_key_value_heads
        self.numKvHeads = config.numKeyValueHeads
        // Python: self.num_key_value_groups = self.num_heads // self.num_key_value_heads
        self.numKeyValueGroups = config.numAttentionHeads / config.numKeyValueHeads
        // Python: self.max_position_embeddings = config.max_position_embeddings
        self.maxPositionEmbeddings = config.maxPositionEmbeddings
        // Python: self.rope_theta = config.rope_theta
        self.ropeTheta = config.ropeTheta
        // Python: self.scale = self.head_dim**-0.5
        self.scale = 1.0 / sqrt(Float(config.headDim))

        // Python: self.q_proj = nn.Linear(self.hidden_size, self.num_heads * self.head_dim, bias=config.attention_bias)
        self._qProj.wrappedValue = Linear(config.hiddenSize, config.numAttentionHeads * config.headDim, bias: config.attentionBias)
        // Python: self.k_proj = nn.Linear(self.hidden_size, self.num_key_value_heads * self.head_dim, bias=config.attention_bias)
        self._kProj.wrappedValue = Linear(config.hiddenSize, config.numKeyValueHeads * config.headDim, bias: config.attentionBias)
        // Python: self.v_proj = nn.Linear(self.hidden_size, self.num_key_value_heads * self.head_dim, bias=config.attention_bias)
        self._vProj.wrappedValue = Linear(config.hiddenSize, config.numKeyValueHeads * config.headDim, bias: config.attentionBias)
        // Python: self.o_proj = nn.Linear(self.num_heads * self.head_dim, self.hidden_size, bias=config.attention_bias)
        self._oProj.wrappedValue = Linear(config.numAttentionHeads * config.headDim, config.hiddenSize, bias: config.attentionBias)

        // Python: initialize_rope with config parameters
        self.rope = RoPE(
            dimensions: config.headDim,
            traditional: false,
            base: config.ropeTheta
        )

        super.init()
    }

    // Legacy constructor for backward compatibility
    public init(hiddenSize: Int, attentionHeads: Int, kvHeads: Int, headDim: Int,
                maxPositionEmbeddings: Int, ropeTheta: Float, bias: Bool) {
        self.headDim = headDim
        self.numHeads = attentionHeads
        self.numKvHeads = kvHeads
        self.numKeyValueGroups = attentionHeads / kvHeads
        self.maxPositionEmbeddings = maxPositionEmbeddings
        self.ropeTheta = ropeTheta
        self.scale = 1.0 / sqrt(Float(headDim))

        // Standard MLX Swift: direct dimension calculation
        self._qProj.wrappedValue = Linear(hiddenSize, attentionHeads * headDim, bias: bias)
        self._kProj.wrappedValue = Linear(hiddenSize, kvHeads * headDim, bias: bias)
        self._vProj.wrappedValue = Linear(hiddenSize, kvHeads * headDim, bias: bias)
        self._oProj.wrappedValue = Linear(attentionHeads * headDim, hiddenSize, bias: bias)

        // Initialize RoPE using MLX Swift
        self.rope = RoPE(dimensions: headDim, traditional: false, base: ropeTheta)

        super.init()
    }

    public func callAsFunction(_ hiddenStates: MLXArray, attentionMask: MLXArray? = nil, cache: (any KVCache)?) -> MLXArray {
        // Python: bsz, q_len, _ = hidden_states.shape
        let bsz = hiddenStates.shape[0]
        let qLen = hiddenStates.shape[1]

        // Python: queries, keys, values = (self.q_proj(hidden_states), self.k_proj(hidden_states), self.v_proj(hidden_states))
        let queries = qProj(hiddenStates)
        let keys = kProj(hiddenStates)
        let values = vProj(hiddenStates)

        // Python: queries = queries.reshape(bsz, q_len, self.num_heads, -1).transpose(0, 2, 1, 3)
        let queriesReshaped = queries.reshaped([bsz, qLen, numHeads, -1])
        let queriesTransposed = queriesReshaped.transposed(0, 2, 1, 3)

        // Python: keys = keys.reshape(bsz, q_len, self.num_key_value_heads, -1).transpose(0, 2, 1, 3)
        let keysReshaped = keys.reshaped([bsz, qLen, numKvHeads, -1])
        let keysTransposed = keysReshaped.transposed(0, 2, 1, 3)

        // Python: values = values.reshape(bsz, q_len, self.num_key_value_heads, -1).transpose(0, 2, 1, 3)
        let valuesReshaped = values.reshaped([bsz, qLen, numKvHeads, -1])
        let valuesTransposed = valuesReshaped.transposed(0, 2, 1, 3)

        var finalQueries: MLXArray
        var finalKeys: MLXArray
        var finalValues: MLXArray

        // Python: if cache is not None:
        if let cache = cache {
            // Python: queries = self.rope(queries, offset=cache.offset)
            finalQueries = rope(queriesTransposed, offset: cache.offset)
            // Python: keys = self.rope(keys, offset=cache.offset)
            let rotatedKeys = rope(keysTransposed, offset: cache.offset)
            // Python: keys, values = cache.update_and_fetch(keys, values)
            (finalKeys, finalValues) = cache.update(keys: rotatedKeys, values: valuesTransposed)
        } else {
            // Python: queries = self.rope(queries)
            finalQueries = rope(queriesTransposed)
            // Python: keys = self.rope(keys)
            finalKeys = rope(keysTransposed)
            finalValues = valuesTransposed
        }

        // CRITICAL FIX: Python calls scaled_dot_product_attention with cache parameter
        // but Swift MLX doesn't have cache parameter, so we handle cache above and pass keys/values with full context
        let output = scaledDotProductAttention(
            queries: finalQueries,
            keys: finalKeys,
            values: finalValues,
            scale: scale,
            mask: attentionMask  // Python: mask=attention_mask - pass through from function parameter
        )

        // Python: output = output.transpose(0, 2, 1, 3).reshape(bsz, q_len, -1)
        let outputTransposed = output.transposed(0, 2, 1, 3)
        let outputReshaped = outputTransposed.reshaped([bsz, qLen, -1])

        // Python: return self.o_proj(output)
        return oProj(outputReshaped)
    }

    // Legacy constructor for backward compatibility
    public func callAsFunction(_ hiddenStates: MLXArray, cache: (any KVCache)?) -> MLXArray {
        return callAsFunction(hiddenStates, attentionMask: nil, cache: cache)
    }
}

/**
 * Standard MLP
 */
/**
 * Direct Python equivalent: class LlamaMLP(nn.Module)
 * Llama MLP with SiLU activation - exact migration from VoxtralLlama.swift
 * Uses @ModuleInfo for quantization support
 */
public class LlamaStandardMLP: Module {
    let config: LlamaStandardConfig
    let hiddenSize: Int
    let intermediateSize: Int
    @ModuleInfo var gateProj: Linear
    @ModuleInfo var upProj: Linear
    @ModuleInfo var downProj: Linear
    let actFn: (MLXArray) -> MLXArray

    /**
     * Direct Python equivalent: def __init__(self, config):
     */
    public init(config: LlamaStandardConfig) {
        // Python: self.config = config
        self.config = config
        // Python: self.hidden_size = config.hidden_size
        self.hiddenSize = config.hiddenSize
        // Python: self.intermediate_size = config.intermediate_size
        self.intermediateSize = config.intermediateSize

        // Python: self.act_fn = nn.silu
        self.actFn = silu

        // Python: self.gate_proj = nn.Linear(self.hidden_size, self.intermediate_size, bias=config.mlp_bias)
        self._gateProj.wrappedValue = Linear(hiddenSize, intermediateSize, bias: config.mlpBias)
        // Python: self.up_proj = nn.Linear(self.hidden_size, self.intermediate_size, bias=config.mlp_bias)
        self._upProj.wrappedValue = Linear(hiddenSize, intermediateSize, bias: config.mlpBias)
        // Python: self.down_proj = nn.Linear(self.intermediate_size, self.hidden_size, bias=config.mlp_bias)
        self._downProj.wrappedValue = Linear(intermediateSize, hiddenSize, bias: config.mlpBias)

        super.init()
    }

    // Legacy constructor for backward compatibility
    public init(hiddenSize: Int, intermediateSize: Int, bias: Bool) {
        let config = LlamaStandardConfig(
            hiddenSize: hiddenSize,
            intermediateSize: intermediateSize,
            mlpBias: bias
        )
        self.config = config
        self.hiddenSize = hiddenSize
        self.intermediateSize = intermediateSize
        self.actFn = silu

        self._gateProj.wrappedValue = Linear(hiddenSize, intermediateSize, bias: bias)
        self._upProj.wrappedValue = Linear(hiddenSize, intermediateSize, bias: bias)
        self._downProj.wrappedValue = Linear(intermediateSize, hiddenSize, bias: bias)

        super.init()
    }

    /**
     * Direct Python equivalent: def __call__(self, hidden_states: mx.array) -> mx.array:
     */
    public func callAsFunction(_ hiddenStates: MLXArray) -> MLXArray {
        // Python: return self.down_proj(self.act_fn(self.gate_proj(hidden_states)) * self.up_proj(hidden_states))
        return downProj(actFn(gateProj(hiddenStates)) * upProj(hiddenStates))
    }
}

/**
 * Standard Audio Encoder - VOXTRAL SPECIFIC
 * Uses @ModuleInfo for quantization support
 */
public class VoxtralStandardEncoder: Module {
    @ModuleInfo var conv1: Conv1d
    @ModuleInfo var conv2: Conv1d
    @ModuleInfo var embedPositions: Embedding
    @ModuleInfo var layers: [VoxtralStandardEncoderLayer]
    @ModuleInfo var layerNorm: LayerNorm

    public init(hiddenSize: Int, intermediateSize: Int, hiddenLayers: Int,
                attentionHeads: Int, kvHeads: Int, headDim: Int,
                maxSourcePositions: Int, numMelBins: Int) {

        // VOXTRAL SPECIFIC: conv2 has stride=2 for temporal compression
        self._conv1.wrappedValue = Conv1d(inputChannels: numMelBins, outputChannels: hiddenSize, kernelSize: 3, padding: 1)
        self._conv2.wrappedValue = Conv1d(inputChannels: hiddenSize, outputChannels: hiddenSize, kernelSize: 3, stride: 2, padding: 1)
        self._embedPositions.wrappedValue = Embedding(embeddingCount: maxSourcePositions, dimensions: hiddenSize)

        self._layers.wrappedValue = (0..<hiddenLayers).map { _ in
            VoxtralStandardEncoderLayer(
                hiddenSize: hiddenSize,
                intermediateSize: intermediateSize,
                attentionHeads: attentionHeads,
                headDim: headDim
            )
        }

        self._layerNorm.wrappedValue = LayerNorm(dimensions: hiddenSize)

        super.init()
    }

    public func callAsFunction(_ inputs: MLXArray) -> MLXArray {
        // Input shape: [batch, n_mels, seq_len] (matches Python)
        // Transpose to [batch, seq_len, n_mels] for Conv1d
        var hiddenStates = inputs.transposed(0, 2, 1)

        // Conv layers with GELU activation (matching Python)
        hiddenStates = gelu(conv1(hiddenStates))
        hiddenStates = gelu(conv2(hiddenStates))

        // Add positional embeddings
        let seqLen = hiddenStates.shape[1]
        let embedPos = embedPositions.weight[0..<seqLen]  // [seqLen, hiddenSize]
        hiddenStates = hiddenStates + embedPos  // Broadcasting: [batch, seqLen, hidden] + [seqLen, hidden]

        // Pass through transformer layers
        for layer in layers {
            hiddenStates = layer(hiddenStates)
        }

        return layerNorm(hiddenStates)
    }
}

/**
 * Audio Attention - uses out_proj instead of o_proj
 * Uses @ModuleInfo for quantization support
 * Implements full multi-head attention matching Python reference
 */
public class AudioAttention: Module {
    @ModuleInfo var qProj: Linear
    @ModuleInfo var kProj: Linear
    @ModuleInfo var vProj: Linear
    @ModuleInfo var outProj: Linear  // audio_tower uses out_proj

    let headDim: Int
    let numHeads: Int
    let embedDim: Int
    let scale: Float

    public init(hiddenSize: Int, attentionHeads: Int, headDim: Int, bias: Bool) {
        self._qProj.wrappedValue = Linear(hiddenSize, attentionHeads * headDim, bias: bias)
        self._kProj.wrappedValue = Linear(hiddenSize, attentionHeads * headDim, bias: false)
        self._vProj.wrappedValue = Linear(hiddenSize, attentionHeads * headDim, bias: bias)
        self._outProj.wrappedValue = Linear(attentionHeads * headDim, hiddenSize, bias: bias)

        self.headDim = headDim
        self.numHeads = attentionHeads
        self.embedDim = hiddenSize
        self.scale = pow(Float(headDim), -0.5)

        super.init()
    }

    public func callAsFunction(_ hiddenStates: MLXArray, cache: (any KVCache)?) -> MLXArray {
        // Get dimensions
        let batchSize = hiddenStates.shape[0]
        let seqLen = hiddenStates.shape[1]

        // Project to Q, K, V
        var query = qProj(hiddenStates)
        var key = kProj(hiddenStates)
        var value = vProj(hiddenStates)

        // Reshape to [batch, seq, heads, head_dim] then transpose to [batch, heads, seq, head_dim]
        query = query.reshaped([batchSize, seqLen, numHeads, headDim]).transposed(0, 2, 1, 3)
        key = key.reshaped([batchSize, seqLen, numHeads, headDim]).transposed(0, 2, 1, 3)
        value = value.reshaped([batchSize, seqLen, numHeads, headDim]).transposed(0, 2, 1, 3)

        // Scaled dot-product attention
        var attnOutput = MLX.scaledDotProductAttention(
            queries: query,
            keys: key,
            values: value,
            scale: scale,
            mask: nil
        )

        // Reshape back: [batch, heads, seq, head_dim] → [batch, seq, heads, head_dim] → [batch, seq, embed_dim]
        attnOutput = attnOutput.transposed(0, 2, 1, 3).reshaped([batchSize, seqLen, embedDim])

        // Final projection
        return outProj(attnOutput)
    }
}

/**
 * Standard Encoder Layer
 * Uses @ModuleInfo for quantization support
 */
public class VoxtralStandardEncoderLayer: Module {
    @ModuleInfo var selfAttn: AudioAttention  // Use AudioAttention for audio_tower
    @ModuleInfo var selfAttnLayerNorm: LayerNorm
    @ModuleInfo var fc1: Linear
    @ModuleInfo var fc2: Linear
    @ModuleInfo var finalLayerNorm: LayerNorm

    public init(hiddenSize: Int, intermediateSize: Int, attentionHeads: Int, headDim: Int) {
        self._selfAttn.wrappedValue = AudioAttention(
            hiddenSize: hiddenSize,
            attentionHeads: attentionHeads,
            headDim: headDim,
            bias: true
        )
        self._selfAttnLayerNorm.wrappedValue = LayerNorm(dimensions: hiddenSize)
        self._fc1.wrappedValue = Linear(hiddenSize, intermediateSize, bias: true)
        self._fc2.wrappedValue = Linear(intermediateSize, hiddenSize, bias: true)
        self._finalLayerNorm.wrappedValue = LayerNorm(dimensions: hiddenSize)

        super.init()
    }
    
    public func callAsFunction(_ hiddenStates: MLXArray) -> MLXArray {
        var hiddenStates = hiddenStates
        var residual = hiddenStates
        hiddenStates = selfAttnLayerNorm(hiddenStates)
        hiddenStates = selfAttn(hiddenStates, cache: nil)
        hiddenStates = residual + hiddenStates
        
        residual = hiddenStates
        hiddenStates = finalLayerNorm(hiddenStates)
        hiddenStates = fc1(hiddenStates)
        hiddenStates = gelu(hiddenStates)
        hiddenStates = fc2(hiddenStates)
        hiddenStates = residual + hiddenStates
        
        return hiddenStates
    }
}

/**
 * Standard Projector - VOXTRAL SPECIFIC
 * Projects from audio intermediate_size (5120) to text hidden_size (3072)
 * Uses @ModuleInfo for quantization support
 */
public class VoxtralStandardProjector: Module {
    @ModuleInfo(key: "linear_1") var linear1: Linear  // Match underscore naming from safetensors
    @ModuleInfo(key: "linear_2") var linear2: Linear  // Match underscore naming from safetensors
    let act: (MLXArray) -> MLXArray

    public init(inputSize: Int, hiddenSize: Int, hiddenAct: String) {
        // VOXTRAL SPECIFIC: Two linear layers with specific dimensions
        // linear_1: audio_intermediate_size (5120) → text_hidden_size (3072)
        // linear_2: text_hidden_size (3072) → text_hidden_size (3072)

        self._linear1.wrappedValue = Linear(inputSize, hiddenSize, bias: false)    // 5120 → 3072
        self._linear2.wrappedValue = Linear(hiddenSize, hiddenSize, bias: false)   // 3072 → 3072

        // Use specified activation (gelu for Voxtral)
        if hiddenAct == "gelu" {
            self.act = MLXNN.gelu
        } else {
            self.act = { silu($0) }
        }

        super.init()
    }
    
    public func callAsFunction(_ inputs: MLXArray) -> MLXArray {
        var hiddenStates = linear1(inputs)
        hiddenStates = act(hiddenStates)
        hiddenStates = linear2(hiddenStates)
        return hiddenStates
    }
}

/**
 * Load weights from safetensors files - EXACT 1:1 Python translation
 * Direct Python equivalent: mlx_voxtral/utils/model_loading.py:load_weights (lines 40-60)
 */
private func loadWeights(from modelURL: URL) throws -> [String: MLXArray] {
    VoxtralDebug.log("Loading weights from safetensors")
    var weights: [String: MLXArray] = [:]

    // Python: weight_files = sorted([f for f in model_path.glob("*.safetensors") ...])
    let weightFiles = try FileManager.default.contentsOfDirectory(at: modelURL, includingPropertiesForKeys: nil)
        .filter { url in
            let name = url.lastPathComponent
            return name.hasSuffix(".safetensors") &&
                   !name.hasPrefix("._") &&
                   !name.hasPrefix("consolidated") &&
                   !name.contains("consolidated.")
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

    // Python: if not weight_files: raise FileNotFoundError(...)
    if weightFiles.isEmpty {
        throw NSError(domain: "VoxtralStandardLoader", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "No weight files found in \(modelURL.path)"
        ])
    }

    VoxtralDebug.log("Found \(weightFiles.count) safetensors files")

    // Python: for wf in weight_files: weights.update(mx.load(str(wf)))
    for weightFile in weightFiles {
        VoxtralDebug.log("Loading \(weightFile.lastPathComponent)")
        let loadedWeights = try loadArrays(url: weightFile)
        for (key, value) in loadedWeights {
            weights[key] = value
        }
    }

    VoxtralDebug.log("Loaded \(weights.count) weight tensors")
    return weights
}

/**
 * Convert snake_case to camelCase for quantization detection.
 * Handles paths like "audio_tower.layers.0.self_attn.k_proj.scales"
 * → "audioTower.layers.0.selfAttn.kProj.scales"
 *
 * IMPORTANT: Preserves numeric suffixes like "linear_1" → "linear_1" (not "linear1")
 * because Swift code uses @ModuleInfo(key: "linear_1") to match Python naming.
 */
private func convertSnakeCaseToCamelCase(_ snakeCaseString: String) -> String {
    // Split by "." to handle each path component separately
    let pathComponents = snakeCaseString.split(separator: ".")

    let convertedComponents = pathComponents.map { component -> String in
        let componentStr = String(component)

        // Skip numeric components (layer indices)
        if Int(componentStr) != nil {
            return componentStr
        }

        // Split by underscore
        let parts = componentStr.split(separator: "_")
        if parts.count == 1 {
            return componentStr
        }

        // Check if last part is a number (e.g., "linear_1", "linear_2")
        // If so, preserve the underscore before the number
        if let lastPart = parts.last, Int(lastPart) != nil {
            // Convert all parts except the last numeric one to camelCase
            let wordParts = parts.dropLast()
            let camelCased = wordParts.enumerated().map { index, part in
                if index == 0 {
                    return String(part)
                } else {
                    return part.capitalized
                }
            }.joined()
            // Append "_N" suffix as-is
            return "\(camelCased)_\(lastPart)"
        }

        // Standard camelCase conversion for word boundaries
        return parts.enumerated().map { index, part in
            if index == 0 {
                return String(part)
            } else {
                return part.capitalized
            }
        }.joined()
    }

    return convertedComponents.joined(separator: ".")
}

/**
 * Analyze weights to detect quantized modules.
 * MLX Swift best practice: know quantization before model creation.
 *
 * Supports mixed-precision quantization where different layers can have different bits/group_size.
 * Config format:
 * - Global defaults: quantization["group_size"] = 64, quantization["bits"] = 4
 * - Per-layer (uniform): quantization["layer.name"] = true (uses global defaults)
 * - Per-layer (mixed): quantization["layer.name"] = {group_size: 64, bits: 6}
 * - Not quantized: quantization["layer.name"] = false
 */
private func detectQuantizedModules(weights: [String: MLXArray], config: VoxtralStandardConfiguration? = nil) -> [String: (groupSize: Int, bits: Int)] {
    var quantizedModules: [String: (groupSize: Int, bits: Int)] = [:]

    // Step 1: Extract global defaults from config
    var defaultGroupSize = 64
    var defaultBits = 8

    if let quantConfig = config?.quantization {
        if case .int(let gs) = quantConfig["group_size"] {
            defaultGroupSize = gs
        }
        if case .int(let b) = quantConfig["bits"] {
            defaultBits = b
        }
    }

    VoxtralDebug.log("Quantization defaults: group_size=\(defaultGroupSize), bits=\(defaultBits)")

    // Step 2: Build per-layer quantization map from config
    // Store both the full path and just the layer suffix for flexible matching
    var perLayerConfig: [String: (groupSize: Int, bits: Int)] = [:]
    var notQuantizedLayers: Set<String> = []

    if let quantConfig = config?.quantization {
        for (layerName, value) in quantConfig {
            // Skip global settings
            if layerName == "group_size" || layerName == "bits" {
                continue
            }

            switch value {
            case .bool(true):
                // Uses global defaults
                perLayerConfig[layerName] = (groupSize: defaultGroupSize, bits: defaultBits)
            case .config(let layerConfig):
                // Per-layer specific config (mixed quantization)
                perLayerConfig[layerName] = (groupSize: layerConfig.groupSize, bits: layerConfig.bits)
            case .bool(false):
                // Explicitly not quantized
                notQuantizedLayers.insert(layerName)
            case .int(_):
                break
            }
        }
    }

    // Debug: Log unique bit configurations found
    var bitConfigs: [Int: Int] = [:]
    for (_, cfg) in perLayerConfig {
        bitConfigs[cfg.bits, default: 0] += 1
    }
    VoxtralDebug.log("Quantization config: \(perLayerConfig.count) layer configs, bits distribution: \(bitConfigs)")

    // Step 3: Look for .scales keys in weights and match with config
    for (key, _) in weights {
        if key.hasSuffix(".scales") {
            // Extract Python-style module path: "audio_tower.layers.0.fc1.scales" -> "audio_tower.layers.0.fc1"
            var pythonModulePath = String(key.dropLast(".scales".count))
            let originalPythonPath = pythonModulePath

            // CRITICAL FIX: Handle the structural difference between weight keys and model paths
            if pythonModulePath.hasPrefix("language_model.") && !pythonModulePath.hasPrefix("language_model.model.") {
                let suffix = String(pythonModulePath.dropFirst("language_model.".count))
                pythonModulePath = "language_model.model.\(suffix)"
            }
            if pythonModulePath == "embed_tokens" {
                pythonModulePath = "language_model.model.embed_tokens"
            }
            if pythonModulePath == "lm_head" {
                pythonModulePath = "language_model.lm_head"
            }

            // Convert to Swift camelCase for the quantizedModules dict
            let swiftModulePath = convertSnakeCaseToCamelCase(pythonModulePath)

            // Try multiple matching strategies for config lookup:
            // 1. Exact match with original path from weights
            // 2. Exact match with modified path
            // 3. Suffix match (for paths that might have different prefixes)
            var foundConfig: (groupSize: Int, bits: Int)? = nil

            // Strategy 1: Direct lookup with original path
            if let cfg = perLayerConfig[originalPythonPath] {
                foundConfig = cfg
            }
            // Strategy 2: Direct lookup with modified path
            else if let cfg = perLayerConfig[pythonModulePath] {
                foundConfig = cfg
            }
            // Strategy 3: Find config entry that matches as suffix
            else {
                for (configPath, cfg) in perLayerConfig {
                    if originalPythonPath.hasSuffix(configPath) || configPath.hasSuffix(originalPythonPath) {
                        foundConfig = cfg
                        break
                    }
                }
            }

            // Check if layer is explicitly not quantized
            let isNotQuantized = notQuantizedLayers.contains(originalPythonPath) ||
                                 notQuantizedLayers.contains { originalPythonPath.hasSuffix($0) }

            if isNotQuantized {
                // Skip - this layer should not be quantized
                continue
            }

            if let layerConfig = foundConfig {
                quantizedModules[swiftModulePath] = layerConfig
            } else {
                // Fallback to global defaults if no per-layer config found
                quantizedModules[swiftModulePath] = (groupSize: defaultGroupSize, bits: defaultBits)
            }
        }
    }

    // Debug: Log final quantization summary
    var finalBitDistribution: [Int: Int] = [:]
    for (_, cfg) in quantizedModules {
        finalBitDistribution[cfg.bits, default: 0] += 1
    }
    VoxtralDebug.log("Quantization applied: \(quantizedModules.count) modules, bits distribution: \(finalBitDistribution)")

    return quantizedModules
}

/**
 * Apply quantization to model using MLX Swift recommended approach.
 * This follows MLXLMCommon pattern and MLX Swift documentation.
 */
func loadQuantizedVoxtral(
    model: Module,
    weights: [String: MLXArray],
    config: VoxtralStandardConfiguration
) -> Module {
    // Python: if "quantization" not in config: return model
    guard config.quantization != nil else {
        return model
    }

    // Step 1: Detect which modules are quantized based on weights AND config
    let quantizedModules = detectQuantizedModules(weights: weights, config: config)

    // Step 2: Apply quantization using MLX Swift standard function
    // Use the filter that returns per-layer (groupSize, bits, mode) for mixed quantization support
    MLXNN.quantize(
        model: model,
        filter: { modulePath, module -> (groupSize: Int, bits: Int, mode: QuantizationMode)? in
            // Get per-layer config from detected quantized modules
            guard let layerConfig = quantizedModules[modulePath] else {
                return nil  // Don't quantize this layer
            }
            return (groupSize: layerConfig.groupSize, bits: layerConfig.bits, mode: .affine)
        }
    )
    VoxtralDebug.log("Quantization applied to \(quantizedModules.count) modules with per-layer config")

    return model
}


/**
 * Standard MLX Swift Model Loading Function
 * Follows exact pattern from all MLX Swift projects
 */
/*
/**
 * EXPERIMENTAL: Load with official MLXLMCommon.Llama for 100% Python compatibility
 * DEPRECATED: Removed due to API complications with MLXLLM wrapper
 */
public func loadVoxtralWithOfficialLlama(
    modelPath: String,
    dtype: MLX.DType = .float16
) throws -> (VoxtralForConditionalGeneration, VoxtralStandardConfiguration) {
    // Load the official Llama and configuration
    let (officialLlama, configuration) = try loadMLXLLMModel(modelPath: modelPath, dtype: dtype)

    // Create VoxtralForConditionalGeneration with official Llama
    let model = VoxtralForConditionalGeneration(officialLlama: officialLlama, config: configuration)

    // Load lm_head weights separately
    let modelWeights = try loadModelWeights(from: modelPath)
    if let lmHeadWeight = modelWeights["lm_head.weight"] {
        model.lm_head.weight = lmHeadWeight
    } else if let embedWeight = modelWeights["language_model.embed_tokens.weight"] {
        model.lm_head.weight = embedWeight
    }

    return (model, configuration)
}
*/

public func loadVoxtralStandardModel(
    modelPath: String,
    dtype: MLX.DType = .float16
) throws -> (VoxtralStandardModel, VoxtralStandardConfiguration) {
    VoxtralDebug.log("Loading Voxtral from \(modelPath)")

    // Step 1: Load configuration
    let modelURL = URL(fileURLWithPath: modelPath)
    let configPath = modelURL.appendingPathComponent("config.json")
    let configData = try Data(contentsOf: configPath)
    let configuration = try JSONDecoder().decode(VoxtralStandardConfiguration.self, from: configData)

    // Step 2: Create model
    let model = VoxtralStandardModel(configuration: configuration)

    // UNIFIED APPROACH: Use same loading pattern for ALL models (quantized and non-quantized)
    // This ensures both paths use the same sanitize() method and parameter name conversion

    // Step 1: Load weights from safetensors (same for both quantized and non-quantized)
    // Different loading approaches for quantized vs non-quantized models
    let finalModel: VoxtralStandardModel
    if configuration.quantization != nil {

        // Step 1: Load raw weights for quantized models
        let weightsData = try loadWeights(from: modelURL)

        // Step 2: Apply quantization structure (transforms Linear -> QuantizedLinear, etc.)
        let quantizedModel = loadQuantizedVoxtral(
            model: model,
            weights: weightsData,
            config: configuration
        ) as! VoxtralStandardModel

        // Step 3: Sanitize weights for quantized models
        let sanitizedWeights = try quantizedModel.sanitize(weightsData)

        // Step 4: Load using ModuleParameters approach that works for quantized
        let parameters = ModuleParameters.unflattened(sanitizedWeights)
        quantizedModel.update(parameters: parameters)

        finalModel = quantizedModel
    } else {
        // For non-quantized models, use the EXACT original approach from commit 99504ee:
        // 1. Load weights manually, 2. Sanitize, 3. Use ModuleParameters.unflattened()

        // Step 1: Load raw weights
        let weightsData = try loadWeights(from: modelURL)

        // Step 2: Sanitize weights using the EXACT sanitize() from commit 99504ee
        let sanitizedWeights = try model.sanitize(weightsData)

        // Step 3: Load using ModuleParameters.unflattened() like in the original
        let parameters = ModuleParameters.unflattened(sanitizedWeights)
        model.update(parameters: parameters)

        finalModel = model
    }
    VoxtralDebug.log("Model loaded successfully")
    return (finalModel, configuration)
}