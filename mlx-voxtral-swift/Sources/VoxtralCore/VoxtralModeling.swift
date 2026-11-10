/**
 * VoxtralModeling - Swift equivalent of mlx.voxtral/modeling_voxtral.py
 * 
 * Exact conversion of Python VoxtralAttention, VoxtralEncoderLayer, VoxtralEncoder,
 * VoxtralMultiModalProjector, and VoxtralForConditionalGeneration classes.
 * Direct line-by-line translation following the rule: "si ça existe en python mlx ça doit exister en mlx swift"
 */

import Foundation
import MLX
import MLXNN
import MLXLMCommon  // For LanguageModel protocol and KVCacheSimple
import MLXLLM       // For official LlamaModel
import MLXRandom

// Global debug dump function - can be set by VoxtralTest2
// Swift 6: nonisolated(unsafe) for debug callback
nonisolated(unsafe) public var writeDebugToDump: (String) -> Void = { message in
    // Default: write to a temporary file
    let debugFile = "/tmp/swift_debug_generation.txt"
    let fileManager = FileManager.default
    if !fileManager.fileExists(atPath: debugFile) {
        fileManager.createFile(atPath: debugFile, contents: nil, attributes: nil)
    }
    if let fileHandle = FileHandle(forWritingAtPath: debugFile) {
        fileHandle.seekToEndOfFile()
        if let data = message.data(using: .utf8) {
            fileHandle.write(data)
        }
        fileHandle.closeFile()
    }
}

/**
 * Direct Python equivalent: @dataclass class VoxtralModelOutput
 */
public struct VoxtralModelOutput {
    public let logits: MLXArray
    public let pastKeyValues: [KVCache]?  // Correct type to match function parameter
    public let hiddenStates: MLXArray?
    public let attentions: [MLXArray]?
    
    public init(
        logits: MLXArray,
        pastKeyValues: [KVCache]? = nil,
        hiddenStates: MLXArray? = nil,
        attentions: [MLXArray]? = nil
    ) {
        self.logits = logits
        self.pastKeyValues = pastKeyValues
        self.hiddenStates = hiddenStates
        self.attentions = attentions
    }
}

/**
 * Direct Python equivalent: class VoxtralAttention(nn.Module)
 */
public class VoxtralAttention: Module {
    
    // Python: def __init__(self, embed_dim: int, num_heads: int, bias: bool = False)
    let embedDim: Int
    let numHeads: Int
    let bias: Bool
    let headDim: Int
    let scaling: Float
    
    // @ModuleInfo required for quantization support
    @ModuleInfo(key: "q_proj") public var qProj: Linear
    @ModuleInfo(key: "k_proj") public var kProj: Linear
    @ModuleInfo(key: "v_proj") public var vProj: Linear
    @ModuleInfo(key: "out_proj") public var outProj: Linear

    public init(embedDim: Int, numHeads: Int, bias: Bool = false) {
        // Python: self.embed_dim = embed_dim
        self.embedDim = embedDim
        // Python: self.num_heads = num_heads
        self.numHeads = numHeads
        // Python: self.bias = bias
        self.bias = bias
        // Python: self.head_dim = embed_dim // num_heads
        self.headDim = embedDim / numHeads
        // Python: self.scaling = (embed_dim // num_heads) ** -0.5
        self.scaling = Float(pow(Double(embedDim / numHeads), -0.5))

        // Initialize with @ModuleInfo wrapper
        // Python: self.q_proj = nn.Linear(embed_dim, embed_dim, bias=bias)
        self._qProj.wrappedValue = Linear(embedDim, embedDim, bias: bias)
        // Python: self.k_proj = nn.Linear(embed_dim, embed_dim, bias=False)  // NO BIAS for k_proj!
        self._kProj.wrappedValue = Linear(embedDim, embedDim, bias: false)
        // Python: self.v_proj = nn.Linear(embed_dim, embed_dim, bias=bias)
        self._vProj.wrappedValue = Linear(embedDim, embedDim, bias: bias)
        // Python: self.out_proj = nn.Linear(embed_dim, embed_dim, bias=bias)
        self._outProj.wrappedValue = Linear(embedDim, embedDim, bias: bias)

        super.init()
    }
    
    /**
     * Direct Python equivalent: def __call__(self, hidden_states: mx.array, attention_mask: Optional[mx.array] = None, output_attentions: bool = False, **kwargs) -> Tuple[mx.array, Optional[mx.array]]
     */
    public func callAsFunction(_ hiddenStates: MLXArray, attentionMask: MLXArray? = nil, outputAttentions: Bool = false) -> (MLXArray, MLXArray?) {
        // Python: batch_size, seq_len, _ = hidden_states.shape
        let batchSize = hiddenStates.shape[0]
        let seqLen = hiddenStates.shape[1]
        
        // Python: query = self.q_proj(hidden_states)
        let query = qProj(hiddenStates)
        // Python: key = self.k_proj(hidden_states)
        let key = kProj(hiddenStates)
        // Python: value = self.v_proj(hidden_states)
        let value = vProj(hiddenStates)
        
        // Python: query = query.reshape(batch_size, seq_len, self.num_heads, self.head_dim).transpose(0, 2, 1, 3)
        let queryReshaped = reshaped(query, [batchSize, seqLen, numHeads, headDim])
        let queryTransposed = transposed(queryReshaped, axes: [0, 2, 1, 3])
        
        // Python: key = key.reshape(batch_size, seq_len, self.num_heads, self.head_dim).transpose(0, 2, 1, 3)
        let keyReshaped = reshaped(key, [batchSize, seqLen, numHeads, headDim])
        let keyTransposed = transposed(keyReshaped, axes: [0, 2, 1, 3])
        
        // Python: value = value.reshape(batch_size, seq_len, self.num_heads, self.head_dim).transpose(0, 2, 1, 3)
        let valueReshaped = reshaped(value, [batchSize, seqLen, numHeads, headDim])
        let valueTransposed = transposed(valueReshaped, axes: [0, 2, 1, 3])
        
        // Python: attn_output = mx.fast.scaled_dot_product_attention(query, key, value, scale=self.scale, mask=attention_mask)
        let attnOutput = scaledDotProductAttention(
            queries: queryTransposed,
            keys: keyTransposed, 
            values: valueTransposed,
            scale: scaling,
            mask: attentionMask
        )
        
        // Python: attn_output = attn_output.transpose(0, 2, 1, 3).reshape(batch_size, seq_len, self.embed_dim)
        let outputTransposed = transposed(attnOutput, axes: [0, 2, 1, 3])
        let outputReshaped = reshaped(outputTransposed, [batchSize, seqLen, embedDim])
        
        // Python: attn_output = self.out_proj(attn_output)
        let finalOutput = outProj(outputReshaped)
        
        // Python: return attn_output, None
        return (finalOutput, nil)
    }
}

/**
 * Direct Python equivalent: class VoxtralEncoderLayer(nn.Module)
 */
public class VoxtralEncoderLayer: Module {

    // Python: def __init__(self, config: VoxtralEncoderConfig)
    let embedDim: Int
    // @ModuleInfo required for quantization support
    @ModuleInfo(key: "self_attn") public var selfAttn: VoxtralAttention
    let self_attn_layer_norm: LayerNorm
    @ModuleInfo public var fc1: Linear
    @ModuleInfo public var fc2: Linear
    let final_layer_norm: LayerNorm
    let activation: (MLXArray) -> MLXArray

    public init(config: VoxtralEncoderConfig) {
        // Python: self.embed_dim = config.hidden_size
        self.embedDim = config.hidden_size

        // Python: self.self_attn_layer_norm = nn.LayerNorm(self.embed_dim, eps=1e-5)
        self.self_attn_layer_norm = LayerNorm(dimensions: embedDim, eps: 1e-5)

        // Python: self.final_layer_norm = nn.LayerNorm(self.embed_dim, eps=1e-5)
        self.final_layer_norm = LayerNorm(dimensions: embedDim, eps: 1e-5)

        // Python: activation based on config.activation_function
        switch config.activation_function {
        case "gelu":
            self.activation = gelu
        case "relu":
            self.activation = relu
        case "silu":
            self.activation = silu
        default:
            self.activation = gelu // Default to GELU
        }

        // Initialize with @ModuleInfo wrapper
        // Python: self.self_attn = VoxtralAttention(...)
        self._selfAttn.wrappedValue = VoxtralAttention(
            embedDim: config.hidden_size,
            numHeads: config.num_attention_heads,
            bias: true
        )

        // Python: self.fc1 = nn.Linear(self.embed_dim, config.intermediate_size, bias=True)
        self._fc1.wrappedValue = Linear(embedDim, config.intermediate_size, bias: true)

        // Python: self.fc2 = nn.Linear(config.intermediate_size, self.embed_dim, bias=True)
        self._fc2.wrappedValue = Linear(config.intermediate_size, embedDim, bias: true)

        super.init()
    }
    
    /**
     * Direct Python equivalent: def __call__(self, hidden_states: mx.array, attention_mask: Optional[mx.array] = None, output_attentions: bool = False, **kwargs) -> Tuple[mx.array, Optional[mx.array]]
     */
    public func callAsFunction(_ hiddenStates: MLXArray, attentionMask: MLXArray? = nil, outputAttentions: Bool = false) -> (MLXArray, MLXArray?) {
        // Python: residual = hidden_states
        let residual = hiddenStates
        
        // Python: hidden_states = self.self_attn_layer_norm(hidden_states)
        let normalizedStates = self_attn_layer_norm(hiddenStates)
        
        // Python: hidden_states, attn_weights = self.self_attn(hidden_states=hidden_states, attention_mask=attention_mask, output_attentions=output_attentions)
        let (attnOutput, attnWeights) = selfAttn(normalizedStates, attentionMask: attentionMask, outputAttentions: outputAttentions)
        
        // Python: hidden_states = residual + hidden_states
        let afterAttnResidual = residual + attnOutput
        
        // Python: residual = hidden_states
        let residual2 = afterAttnResidual
        
        // Python: hidden_states = self.final_layer_norm(hidden_states)
        let normalizedStates2 = final_layer_norm(afterAttnResidual)
        
        // Python: hidden_states = self.activation_fn(self.fc1(hidden_states))
        let fc1Output = fc1(normalizedStates2)
        let activatedStates = activation(fc1Output)
        
        // Python: hidden_states = self.fc2(hidden_states)
        let fc2Output = fc2(activatedStates)
        
        // Python: hidden_states = residual + hidden_states
        let finalOutput = residual2 + fc2Output
        
        // Python: return hidden_states, attn_weights
        return (finalOutput, attnWeights)
    }
}

/**
 * Direct Python equivalent: class VoxtralEncoder(nn.Module)
 */
public class VoxtralEncoder: Module {
    
    // Python: embed_dim = config.hidden_size
    let embedDim: Int
    // Python: self.num_mel_bins = config.num_mel_bins  
    let numMelBins: Int
    // Python: self.padding_idx = config.pad_token_id
    let paddingIdx: Int
    // Python: self.max_source_positions = config.max_source_positions
    let maxSourcePositions: Int
    // Python: self.embed_scale = math.sqrt(embed_dim) if config.scale_embedding else 1.0
    let embedScale: Float
    
    // @ModuleInfo required for weight loading
    @ModuleInfo public var conv1: Conv1d
    @ModuleInfo public var conv2: Conv1d
    @ModuleInfo(key: "embed_positions") public var embedPositions: Embedding
    @ModuleInfo public var layers: [VoxtralEncoderLayer]
    @ModuleInfo(key: "layer_norm") public var layerNorm: LayerNorm
    
    public init(config: VoxtralEncoderConfig) {
        // Python: embed_dim = config.hidden_size
        self.embedDim = config.hidden_size
        // Python: self.num_mel_bins = config.num_mel_bins
        self.numMelBins = config.num_mel_bins
        // Python: self.padding_idx = config.pad_token_id
        self.paddingIdx = config.pad_token_id
        // Python: self.max_source_positions = config.max_source_positions
        self.maxSourcePositions = config.max_source_positions
        // Python: self.embed_scale = math.sqrt(embed_dim) if config.scale_embedding else 1.0
        self.embedScale = config.scale_embedding ? sqrt(Float(embedDim)) : 1.0
        
        // Initialize with @ModuleInfo wrapper
        // Python: self.conv1 = nn.Conv1d(self.num_mel_bins, embed_dim, kernel_size=3, padding=1)
        self._conv1.wrappedValue = Conv1d(
            inputChannels: numMelBins,
            outputChannels: embedDim,
            kernelSize: 3,
            padding: 1
        )

        // Python: self.conv2 = nn.Conv1d(embed_dim, embed_dim, kernel_size=3, stride=2, padding=1)
        self._conv2.wrappedValue = Conv1d(
            inputChannels: embedDim,
            outputChannels: embedDim,
            kernelSize: 3,
            stride: 2,
            padding: 1
        )

        // Python: self.embedPositions = nn.Embedding(self.max_source_positions, embed_dim)
        self._embedPositions.wrappedValue = Embedding(embeddingCount: maxSourcePositions, dimensions: embedDim)

        // Python: self.layerNorm = nn.LayerNorm(embed_dim)
        self._layerNorm.wrappedValue = LayerNorm(dimensions: embedDim)

        // Python: self.layers = [VoxtralEncoderLayer(config) for _ in range(config.num_hidden_layers)]
        self._layers.wrappedValue = (0..<config.num_hidden_layers).map { _ in
            VoxtralEncoderLayer(config: config)
        }

        super.init()
    }
    
    /**
     * Direct Python equivalent: def _prepare_attention_mask(self, attention_mask: mx.array) -> mx.array
     */
    private func prepareAttentionMask(_ attentionMask: MLXArray) -> MLXArray {
        // Python: batch_size, seq_len = attention_mask.shape
        let batchSize = attentionMask.shape[0]
        let seqLen = attentionMask.shape[1]
        
        // Python: attention_mask = attention_mask[:, None, None, :]
        let expandedMask = expandedDimensions(expandedDimensions(attentionMask, axis: 1), axis: 2)
        
        // Python: attention_mask = (1.0 - attention_mask) * -1e4
        let invertedMask = (MLXArray(1.0) - expandedMask) * MLXArray(-1e4)
        
        // Python: return mx.broadcast_to(attention_mask, (batch_size, 1, seq_len, seq_len))
        return broadcast(invertedMask, to: [batchSize, 1, seqLen, seqLen])
    }
    
    /**
     * Direct Python equivalent: def __call__(self, input_features: mx.array, attention_mask: Optional[mx.array] = None, output_attentions: bool = False, output_hidden_states: bool = False) -> Tuple[mx.array, Optional[Tuple[mx.array]], Optional[Tuple[mx.array]]]
     */
    public func callAsFunction(
        _ inputFeatures: MLXArray,
        attentionMask: MLXArray? = nil,
        outputAttentions: Bool = false,
        outputHiddenStates: Bool = false
    ) -> (MLXArray, [MLXArray]?, [MLXArray]?) {
        VoxtralDebug.log("🔍 VoxtralEncoder: input=\(inputFeatures.shape)")

        // Python: hidden_states = input_features.transpose(0, 2, 1)
        var hiddenStates = transposed(inputFeatures, axes: [0, 2, 1])

        // Python: hidden_states = nn.gelu(self.conv1(hidden_states))
        hiddenStates = gelu(conv1(hiddenStates))

        // Python: hidden_states = nn.gelu(self.conv2(hidden_states))
        hiddenStates = gelu(conv2(hiddenStates))
        
        // Python: seq_len = hidden_states.shape[1]
        let seqLen = hiddenStates.shape[1]
        // Python: embed_pos = self.embedPositions.weight[:seq_len]
        let embedPos = self.embedPositions.weight[0..<seqLen]
        // Python: hidden_states = hidden_states + embed_pos
        hiddenStates = hiddenStates + embedPos
        
        // Python: if attention_mask is not None:
        var preparedMask: MLXArray? = nil
        if let mask = attentionMask {
            // Python: attention_mask = self._prepare_attention_mask(attention_mask)
            preparedMask = prepareAttentionMask(mask)
        }
        
        // Python: all_hidden_states = () if output_hidden_states else None
        var allHiddenStates: [MLXArray]? = outputHiddenStates ? [] : nil
        // Python: all_attentions = () if output_attentions else None  
        var allAttentions: [MLXArray]? = outputAttentions ? [] : nil
        
        // Python: for layer in self.layers:
        for layer in layers {
            // Python: if output_hidden_states: all_hidden_states += (hidden_states,)
            if outputHiddenStates {
                allHiddenStates?.append(hiddenStates)
            }
            
            // Python: hidden_states, attn_weights = layer(hidden_states, attention_mask=attention_mask, output_attentions=output_attentions)
            let (layerOutput, attnWeights) = layer(hiddenStates, attentionMask: preparedMask, outputAttentions: outputAttentions)
            hiddenStates = layerOutput
            
            // Python: if output_attentions: all_attentions += (attn_weights,)
            if outputAttentions, let weights = attnWeights {
                allAttentions?.append(weights)
            }
        }
        
        // Python: hidden_states = self.layerNorm(hidden_states)
        hiddenStates = self.layerNorm(hiddenStates)
        
        // Python: if output_hidden_states: all_hidden_states += (hidden_states,)
        if outputHiddenStates {
            allHiddenStates?.append(hiddenStates)
        }
        
        // Python: return hidden_states, all_hidden_states, all_attentions
        return (hiddenStates, allHiddenStates, allAttentions)
    }
}

/**
 * Direct Python equivalent: class VoxtralMultiModalProjector(nn.Module)
 */
public class VoxtralMultiModalProjector: Module {

    // @ModuleInfo required for quantization support
    @ModuleInfo(key: "linear_1") public var linear1: Linear
    // Python: self.act = nn.GELU()
    let act: (MLXArray) -> MLXArray
    @ModuleInfo(key: "linear_2") public var linear2: Linear

    public init(config: VoxtralConfig) {
        // Python: self.act = nn.GELU()
        self.act = gelu

        // Initialize with @ModuleInfo wrapper
        // Python: self.linear1 = nn.Linear(config.audio_config.intermediate_size, config.text_config.hidden_size, bias=False)
        self._linear1.wrappedValue = Linear(config.audio_config.intermediate_size, config.text_config.hiddenSize, bias: false)

        // Python: self.linear2 = nn.Linear(config.text_config.hidden_size, config.text_config.hidden_size, bias=False)
        self._linear2.wrappedValue = Linear(config.text_config.hiddenSize, config.text_config.hiddenSize, bias: false)

        super.init()
    }

    /**
     * Direct Python equivalent: def __call__(self, audio_features: mx.array) -> mx.array
     */
    public func callAsFunction(_ audioFeatures: MLXArray) -> MLXArray {
        // Python: hidden_states = self.linear1(audio_features)
        let hiddenStates = linear1(audioFeatures)
        // Python: hidden_states = self.act(hidden_states)
        let activatedStates = act(hiddenStates)
        // Python: hidden_states = self.linear2(hidden_states)
        return linear2(activatedStates)
    }
}

/**
 * Direct Python equivalent: class VoxtralForConditionalGeneration(nn.Module)
 */
public class VoxtralForConditionalGeneration: Module, LanguageModel {

    public let config: VoxtralConfig
    public let textConfig: VoxtralConfig.TextConfig

    // @ModuleInfo required for quantization support
    @ModuleInfo(key: "audio_tower") public var audioTower: VoxtralEncoder
    @ModuleInfo(key: "multi_modal_projector") public var multiModalProjector: VoxtralMultiModalProjector

    // CRITICAL: Store reference to standardModel for using loaded audio components
    // Internal access needed for VoxtralHybridEncoder extension to use loaded audio tower
    var standardModel: VoxtralStandardModel?
    // Python: self.language_model = LlamaModel(text_config)  
    // Swift: Use LlamaModel for non-quantized, LlamaModelWrapper for quantized models
    @ModuleInfo public var language_model: Module  // Can be LlamaModel or LlamaModelWrapper
    
    // Python: self.embed_tokens = self.language_model.embed_tokens
    // Swift: Real property that shares the same instance (can be Embedding or QuantizedEmbedding)
    @ModuleInfo public var embed_tokens: Module
    // Python: self.lm_head = nn.Linear(text_config.hidden_size, text_config.vocab_size, bias=False)
    @ModuleInfo public var lm_head: Module  // Can be Linear or QuantizedLinear
    
    public init(config: VoxtralConfig) {
        self.config = config
        
        // Python: if isinstance(config.text_config, dict): text_config = VoxtralTextConfig(**config.text_config)
        // Python: else: text_config = config.text_config
        self.textConfig = config.text_config
        
        // 🎯 APPROACH A: Initialize properties BEFORE super.init() (required without @ModuleInfo)
        // Follow Python initialization order but create objects before super.init()
        
        // Python: self.language_model = LlamaModel(text_config) - FIRST!
        // Create LlamaConfig from TextConfig for compatibility
        let llamaConfig = LlamaConfig(
            vocabSize: textConfig.vocabularySize,
            hiddenSize: textConfig.hiddenSize,
            intermediateSize: textConfig.intermediateSize,
            numHiddenLayers: textConfig.numberOfHiddenLayers,
            numAttentionHeads: textConfig.numberOfAttentionHeads,
            numKeyValueHeads: textConfig.numberOfKeyValueHeads,
            headDim: textConfig.headDimension,  // CRITICAL FIX: Pass headDim from config
            maxPositionEmbeddings: textConfig.maxPositionEmbeddings,
            ropeTheta: Float(textConfig.ropeTheta),
            rmsNormEps: Float(textConfig.rmsNormEpsilon)
        )
        self.language_model = LlamaModel(config: llamaConfig)
        
        // Python: self._audioTower.wrappedValue = VoxtralEncoder(config.audio_config) - SECOND
        // Create VoxtralEncoderConfig from AudioConfig
        let encoderConfig = VoxtralEncoderConfig(
            hidden_size: config.audioConfig.hiddenSize,
            intermediate_size: config.audioConfig.intermediate_size,
            num_hidden_layers: config.audioConfig.numLayers,
            num_attention_heads: config.audioConfig.numAttentionHeads
        )
        self._audioTower.wrappedValue = VoxtralEncoder(config: encoderConfig)
        
        // Python: self._multiModalProjector.wrappedValue = VoxtralMultiModalProjector(config) - THIRD  
        self._multiModalProjector.wrappedValue = VoxtralMultiModalProjector(config: config)
        
        // Python: self.lm_head = nn.Linear(...) - LAST!
        self.lm_head = Linear(textConfig.hiddenSize, textConfig.vocabularySize, bias: false)
        
        // Python: self.embed_tokens = self.language_model.embed_tokens
        // Create a placeholder - actual embedding will be accessed via language_model
        self.embed_tokens = Embedding(embeddingCount: textConfig.vocabularySize, dimensions: textConfig.hiddenSize)
        
        super.init()
    }
    
    // Helper function to call language_model regardless of its concrete type
    private func callLanguageModel(inputs: MLXArray?, mask: MLXArray?, cache: [any KVCache]?, inputsEmbeds: MLXArray?) -> MLXArray {
        if let llamaModel = language_model as? LlamaModel {
            return llamaModel(inputs: inputs, mask: mask, cache: cache, inputsEmbeds: inputsEmbeds)
        } else if let llamaModelWrapper = language_model as? LlamaModelWrapper {
            return llamaModelWrapper(inputs ?? MLXArray.zeros([1, 1]), cache: cache)
        } else if let llamaStandardModel = language_model as? LlamaStandardModel {
            return llamaStandardModel.callAsFunction(inputs: inputs, mask: mask, cache: cache, inputsEmbeds: inputsEmbeds)
        } else {
            fatalError("Unsupported language_model type: \(type(of: language_model))")
        }
    }

    /**
     * Constructor from pre-loaded VoxtralStandardModel
     * Used to wrap our validated standard loader
     *
     * WARNING: This creates new empty components but with loaded language_model/lm_head
     * The audio_tower and multi_modal_projector will need weight copying after creation
     */
    public init(standardModel: VoxtralStandardModel) {
        // Convert to simple config - CRITICAL: Use actual model values, not defaults!
        let audioConfig = VoxtralConfig.AudioConfig(
            hiddenSize: standardModel.configuration.audioConfig.hiddenSize,
            numAttentionHeads: standardModel.configuration.audioConfig.attentionHeads,
            numLayers: standardModel.configuration.audioConfig.hiddenLayers,
            intermediate_size: standardModel.configuration.audioConfig.intermediateSize  // 5120, not 4096!
        )
        // FIX: Use actual text config values from model, not defaults!
        let textConfig = VoxtralConfig.TextConfig(
            vocabularySize: standardModel.configuration.textConfig.vocabularySize,
            hiddenSize: standardModel.configuration.textConfig.hiddenSize,  // 3072 for mini-3b
            intermediateSize: standardModel.configuration.textConfig.intermediateSize,
            numberOfHiddenLayers: standardModel.configuration.textConfig.hiddenLayers,
            numberOfAttentionHeads: standardModel.configuration.textConfig.attentionHeads,
            numberOfKeyValueHeads: standardModel.configuration.textConfig.kvHeads,
            headDimension: standardModel.configuration.textConfig.headDim ?? 128,
            maxPositionEmbeddings: standardModel.configuration.textConfig.maxPositionEmbeddings,
            ropeTheta: Double(standardModel.configuration.textConfig.ropeTheta),
            rmsNormEpsilon: Double(standardModel.configuration.textConfig.rmsNormEps)
        )

        self.config = VoxtralConfig(
            audioConfig: audioConfig,
            textConfig: textConfig,
            audioTokenId: standardModel.configuration.audioTokenId
        )

        self.textConfig = textConfig

        // Use the validated language model components directly
        self.language_model = standardModel.languageModel.model
        self.lm_head = standardModel.languageModel.lmHead

        // Create empty components for compatibility (weights need to be copied later)
        let encoderConfig = VoxtralEncoderConfig(
            vocab_size: standardModel.configuration.audioConfig.vocabularySize,
            hidden_size: standardModel.configuration.audioConfig.hiddenSize,
            intermediate_size: standardModel.configuration.audioConfig.intermediateSize,
            num_hidden_layers: standardModel.configuration.audioConfig.hiddenLayers,
            num_attention_heads: standardModel.configuration.audioConfig.attentionHeads,
            num_mel_bins: standardModel.configuration.audioConfig.numMelBins,
            max_source_positions: standardModel.configuration.audioConfig.maxSourcePositions,
            head_dim: standardModel.configuration.audioConfig.headDim,
            num_key_value_heads: standardModel.configuration.audioConfig.kvHeads
        )

        self._audioTower.wrappedValue = VoxtralEncoder(config: encoderConfig)
        self._multiModalProjector.wrappedValue = VoxtralMultiModalProjector(config: self.config)

        // CRITICAL: Store reference to use loaded audio components
        self.standardModel = standardModel

        super.init()

        // Debug info (only shown when VoxtralDebug.enabled = true)
        VoxtralDebug.log("🔍 VoxtralForConditionalGeneration init: lm_head=\(type(of: self.lm_head))")
    }

    /**
     * Constructor for official MLXLLM.LlamaModel (BEST - 100% Python compatibility)
     */
    public init(officialLlama: LlamaModel, config: VoxtralStandardConfiguration) {
        VoxtralDebug.log("🔧 Creating VoxtralForConditionalGeneration with official Llama")

        // Convert to simple config - CRITICAL: Use actual model values, not defaults!
        let audioConfig = VoxtralConfig.AudioConfig(
            hiddenSize: config.audioConfig.hiddenSize,
            numAttentionHeads: config.audioConfig.attentionHeads,
            numLayers: config.audioConfig.hiddenLayers,
            intermediate_size: config.audioConfig.intermediateSize  // 5120, not 4096!
        )
        let textConfig = VoxtralConfig.TextConfig()

        self.config = VoxtralConfig(
            audioConfig: audioConfig,
            textConfig: textConfig,
            audioTokenId: config.audioTokenId
        )

        self.textConfig = textConfig

        // Use the official Llama directly (no wrapper layer!)
        self.language_model = officialLlama

        // For lm_head, we need to extract it from the official Llama
        // The official Llama has an output projection that we can use
        self.lm_head = Linear(config.textConfig.hiddenSize, config.textConfig.vocabularySize, bias: false)

        // Create audio components (need weight loading separately)
        let encoderConfig = VoxtralEncoderConfig(
            vocab_size: config.audioConfig.vocabularySize,
            hidden_size: config.audioConfig.hiddenSize,
            intermediate_size: config.audioConfig.intermediateSize,
            num_hidden_layers: config.audioConfig.hiddenLayers,
            num_attention_heads: config.audioConfig.attentionHeads,
            num_mel_bins: config.audioConfig.numMelBins,
            max_source_positions: config.audioConfig.maxSourcePositions,
            head_dim: config.audioConfig.headDim,
            num_key_value_heads: config.audioConfig.kvHeads
        )

        self._audioTower.wrappedValue = VoxtralEncoder(config: encoderConfig)
        self._multiModalProjector.wrappedValue = VoxtralMultiModalProjector(config: self.config)

        super.init()
        VoxtralDebug.log("✅ VoxtralForConditionalGeneration created with official Llama")
    }

    // Helper function to get layers count for cache initialization
    public func getLanguageModelLayerCount() -> Int {
        if let llamaModel = language_model as? LlamaModel {
            return llamaModel.layers.count
        } else if let llamaModelWrapper = language_model as? LlamaModelWrapper {
            return llamaModelWrapper.layers.count
        } else if let llamaStandardModel = language_model as? LlamaStandardModel {
            return llamaStandardModel.layers.count
        } else {
            fatalError("Unsupported language_model type: \(type(of: language_model))")
        }
    }
    
    /**
     * Direct Python equivalent: def get_audio_embeds(self, input_features: mx.array) -> mx.array
     *
     * 🚀 OPTIMIZED: Process all audio chunks in a single batch instead of looping
     * Before: O(numChunks) separate forward passes through audio tower
     * After: O(1) single batched forward pass - better GPU utilization
     *
     * Input shape: [numChunks, 128, 3000]
     * Output shape: [1, numChunks * 375, hidden_size]
     */
    public func getAudioEmbeds(_ inputFeatures: MLXArray) -> MLXArray {

        // Process ALL chunks through audio tower at once (batched)
        // [numChunks, 128, 3000] -> [numChunks, 1500, 1280]
        let audioHiddenStates: MLXArray
        if let stdModel = standardModel {
            // VoxtralStandardEncoder supports batched input [batch, n_mels, seq_len]
            audioHiddenStates = stdModel.audioTower(inputFeatures)
        } else {
            // Fallback to empty VoxtralEncoder (for non-standard init paths)
            let (hiddenStates, _, _) = audioTower(inputFeatures, outputAttentions: false, outputHiddenStates: false)
            audioHiddenStates = hiddenStates
        }

        // Reshape all chunks at once: [numChunks, 1500, 1280] -> [numChunks * 375, 5120]
        // Math: numChunks * 1500 * 1280 / 5120 = numChunks * 375
        let audioHiddenStatesProcessed = reshaped(audioHiddenStates, [-1, config.audio_config.intermediate_size])

        // Project ALL through multi_modal_projector at once
        // [numChunks * 375, 5120] -> [numChunks * 375, hidden_size]
        let audioEmbeds: MLXArray
        if let stdModel = standardModel {
            audioEmbeds = stdModel.multiModalProjector(audioHiddenStatesProcessed)
        } else {
            audioEmbeds = multiModalProjector(audioHiddenStatesProcessed)
        }

        // Add batch dimension: [numChunks * 375, hidden_size] -> [1, numChunks * 375, hidden_size]
        let finalEmbeds = expandedDimensions(audioEmbeds, axis: 0)

        // Force evaluation to materialize results
        MLX.eval(finalEmbeds)

        if VoxtralDebug.enabled {
            let swiftSum = finalEmbeds.sum().item(Float.self)
            let swiftMean = finalEmbeds.mean().item(Float.self)
            VoxtralDebug.log("AUDIO EMBEDS: shape=\(finalEmbeds.shape), sum=\(swiftSum), mean=\(swiftMean)")
        }

        return finalEmbeds
    }
    
    /**
     * Direct Python equivalent: def _merge_input_embeddings(self, input_ids: Optional[mx.array] = None, input_features: Optional[mx.array] = None, inputs_embeds: Optional[mx.array] = None) -> mx.array
     *
     * OPTIMIZED VERSION: Uses vectorized MLX operations instead of CPU loops.
     * Before: O(seqLength) CPU loops with .item() calls → ~25 seconds
     * After: O(1) GPU operations with cumsum/takeAlong/where → <1 second expected
     */
    // Swift 6: nonisolated(unsafe) for debug counter
    nonisolated(unsafe) private static var _mergeCallCount = 0
    private func mergeInputEmbeddings(
        inputIds: MLXArray? = nil,
        inputFeatures: MLXArray? = nil,
        inputsEmbeds: MLXArray? = nil
    ) -> MLXArray {
        VoxtralForConditionalGeneration._mergeCallCount += 1

        // Python: if inputs_embeds is None:
        var embeddings: MLXArray
        if let embeds = inputsEmbeds {
            embeddings = embeds
        } else {
            guard let ids = inputIds else {
                fatalError("Either input_ids or inputs_embeds must be provided")
            }
            // Python: inputs_embeds = self.embed_tokens(input_ids)
            if let llamaModel = language_model as? LlamaModel {
                embeddings = llamaModel.embedTokens(ids)
            } else if let llamaModelWrapper = language_model as? LlamaModelWrapper {
                if let quantizedEmbedding = llamaModelWrapper.embed_tokens as? QuantizedEmbedding {
                    embeddings = quantizedEmbedding(ids)
                } else {
                    embeddings = llamaModelWrapper.embed_tokens(ids)
                }
            } else if let llamaStandardModel = language_model as? LlamaStandardModel {
                embeddings = llamaStandardModel.embedTokens(ids)
            } else {
                fatalError("Unsupported language_model type: \(type(of: language_model))")
            }
        }

        // Python: if input_features is None or input_ids is None: return inputs_embeds
        guard let features = inputFeatures,
              let ids = inputIds else {
            return embeddings
        }

        // Python: audio_embeds = self.get_audio_embeds(input_features)
        let audioEmbeds = getAudioEmbeds(features)

        // Python: audio_token_mask = input_ids == self.config.audio_token_id
        let audioTokenMask = equal(ids, MLXArray(config.audio_token_id))

        // 🚀 VECTORIZED MERGE: Replace CPU loops with GPU operations
        //
        // The key insight:
        // - audioTokenMask[i,j] = true if position j should have audio
        // - Audio embeddings are sequential: first audio position gets audioEmbeds[0], etc.
        // - cumsum of the mask gives us the audio index for each position
        //
        // Example: mask = [0,0,1,1,1,0,0,1,1,...]
        //          cumsum-1 = [-1,-1,0,1,2,2,2,3,4,...] (clipped to 0)
        //          At mask=true positions, this gives the correct audio embedding index

        let numAudioTokens = audioEmbeds.shape[1]

        // Step 1: Compute audio indices for each position using cumulative sum
        // cumsum of mask gives: [0,0,1,2,3,3,3,4,5,...] for mask [0,0,1,1,1,0,0,1,1,...]
        // Subtract 1 and clip to get valid indices
        let audioMaskInt = audioTokenMask.asType(.int32)  // [batch, seqLen]
        let cumAudioIdx = cumsum(audioMaskInt, axis: 1) - 1  // [batch, seqLen]
        let audioIdxClipped = clip(cumAudioIdx, min: 0, max: numAudioTokens - 1)  // [batch, seqLen]

        // Step 2: Gather audio embeddings using simple take (more efficient than takeAlong with broadcast)
        // For batch=1, we can flatten and use direct indexing
        // audioEmbeds: [1, numAudioTokens, hiddenSize] -> [numAudioTokens, hiddenSize]
        let audioEmbedsFlat = audioEmbeds.squeezed(axis: 0)  // [numAudioTokens, hiddenSize]
        // audioIdxClipped: [1, seqLen] -> [seqLen]
        let indicesFlat = audioIdxClipped.squeezed(axis: 0)  // [seqLen]
        // Gather: [seqLen] indices into [numAudioTokens, hiddenSize] -> [seqLen, hiddenSize]
        let audioEmbedsGathered2D = take(audioEmbedsFlat, indicesFlat, axis: 0)  // [seqLen, hiddenSize]
        // Expand back to [1, seqLen, hiddenSize]
        let audioEmbedsGathered = expandedDimensions(audioEmbedsGathered2D, axis: 0)  // [batch, seqLen, hiddenSize]

        // Step 3: Use where() to select between audio and text embeddings
        let maskExpanded = expandedDimensions(audioTokenMask, axis: -1)  // [batch, seqLen, 1]
        let finalEmbeddings = which(maskExpanded, audioEmbedsGathered, embeddings)  // [batch, seqLen, hiddenSize]

        // Force evaluation
        eval(finalEmbeddings)

        return finalEmbeddings
    }
    
    /**
     * Direct Python equivalent: def __call__(self, input_ids: Optional[mx.array] = None, attention_mask: Optional[mx.array] = None, input_features: Optional[mx.array] = None, inputs_embeds: Optional[mx.array] = None, labels: Optional[mx.array] = None, past_key_values: Optional[List[KVCache]] = None, return_dict: bool = True) -> VoxtralModelOutput
     */
    public func callAsFunction(
        inputIds: MLXArray? = nil,
        attentionMask: MLXArray? = nil,
        inputFeatures: MLXArray? = nil,
        inputsEmbeds: MLXArray? = nil,
        labels: MLXArray? = nil,
        pastKeyValues: [KVCache]? = nil,
        returnDict: Bool = true
    ) -> VoxtralModelOutput {
        // 🎯 CRITICAL DEBUG: Monitor the forward pass for position 385
        var forwardDebugMessage = ""
        let isFirstIteration = pastKeyValues?.first?.offset == 0
        let hasCache = pastKeyValues != nil && !pastKeyValues!.isEmpty
        
        if isFirstIteration {
            forwardDebugMessage += "\n🔥 FORWARD PASS DEBUG (First iteration - Position 385):\n"
        } else if hasCache {
            forwardDebugMessage += "\n🔥 FORWARD PASS DEBUG (Subsequent iteration):\n"
        }
        
        // Python: inputs_embeds = self._merge_input_embeddings(input_ids=input_ids, input_features=input_features, inputs_embeds=inputs_embeds)
        let inputsEmbeds = mergeInputEmbeddings(
            inputIds: inputIds,
            inputFeatures: inputFeatures,
            inputsEmbeds: inputsEmbeds
        )
        
        if isFirstIteration || hasCache {
            let embedsStats = "min=\(inputsEmbeds.min().item(Float.self)), max=\(inputsEmbeds.max().item(Float.self)), mean=\(inputsEmbeds.mean().item(Float.self))"
            forwardDebugMessage += "  Inputs embeds shape: \(inputsEmbeds.shape), stats: \(embedsStats)\n"
            
            // 🎯 CRITICAL: Capture exact embedding values at position 384 (last position before 385)
            let sequenceLength = inputsEmbeds.shape[1]
            if sequenceLength >= 384 {
                let lastPositionEmbed = inputsEmbeds[0, sequenceLength - 1]  // [3072]
                let embedFlat = lastPositionEmbed.flattened()
                var embedFirst10: [String] = []
                for i in 0..<min(10, embedFlat.count) {
                    let val = embedFlat[i].item(Float.self)
                    embedFirst10.append(String(format: "%.8f", val))
                }
                forwardDebugMessage += "  🎯 Position \(sequenceLength-1) embedding first 10: \(embedFirst10)\n"
                
                let lastEmbedStats = "min=\(lastPositionEmbed.min().item(Float.self)), max=\(lastPositionEmbed.max().item(Float.self)), mean=\(lastPositionEmbed.mean().item(Float.self))"
                forwardDebugMessage += "  🎯 Position \(sequenceLength-1) embed stats: \(lastEmbedStats)\n"
            }
        }
        
        // Python: hidden_states = self.language_model(inputs_embeds=inputs_embeds, mask=attention_mask, cache=past_key_values)
        let hiddenStates = callLanguageModel(
            inputs: nil,
            mask: attentionMask,
            cache: pastKeyValues,
            inputsEmbeds: inputsEmbeds
        )
        
        // Apply lm_head to get logits
        let logits: MLXArray
        if let quantizedLinear = lm_head as? QuantizedLinear {
            logits = quantizedLinear(hiddenStates)
        } else if let linear = lm_head as? Linear {
            logits = linear(hiddenStates)
        } else {
            fatalError("Unsupported lm_head type: \(type(of: lm_head))")
        }
        
        // Python: return VoxtralModelOutput(logits=logits, past_key_values=past_key_values, hidden_states=None, attentions=None)
        return VoxtralModelOutput(
            logits: logits,
            pastKeyValues: pastKeyValues,  // Return the cache (modified by reference in language_model)
            hiddenStates: nil,
            attentions: nil
        )
    }
    
    /**
     * Direct Python equivalent: @classmethod def from_pretrained(cls, model_path: str) -> VoxtralForConditionalGeneration
     */
    public static func fromPretrained(_ modelPath: String) throws -> VoxtralForConditionalGeneration {
        // Python: config = VoxtralConfig.from_pretrained(model_path)
        // Python: model = cls(config)
        // Python: model.load_weights(model_path)
        
        // For now, create with default config - should be implemented with actual loading
        let _ = VoxtralConfig()
        // Python: model = VoxtralForConditionalGeneration(config)
        // Python: model.load_state_dict(weights)
        let model = try VoxtralForConditionalGeneration(path: modelPath)
        
        VoxtralDebug.log("Model loaded from \(modelPath)")
        
        return model
    }
    
    /**
     * Direct Python equivalent: def generate(self, **kwargs) -> MLXArray
     */
    public func generate(
        inputIds: MLXArray,
        inputFeatures: MLXArray? = nil,
        attentionMask: MLXArray? = nil,
        maxNewTokens: Int = 100,
        temperature: Float = 1.0,
        topP: Float = 0.95,
        repetitionPenalty: Float = 1.2
    ) throws -> MLXArray {
        // Python: return self.generate_stream(**kwargs).collect()
        
        // ⚠️ REMOVED: Don't call callAsFunction here - it would process audio twice!
        // Python only processes audio once in generate_stream via _merge_input_embeddings
        
        // Return input_ids extended with generated tokens
        // Python equivalent: calls generate_stream and concatenates results
        var generated = inputIds
        
        // 🚀 generateStream now returns [Int] directly
        do {
            let tokenIds = try generateStream(
                inputIds: inputIds,
                inputFeatures: inputFeatures,
                attentionMask: attentionMask,
                maxNewTokens: maxNewTokens,
                temperature: temperature,
                topP: topP,
                repetitionPenalty: repetitionPenalty
            )

            // Append all generated tokens at once
            if !tokenIds.isEmpty {
                let tokenArray = MLXArray(tokenIds.map { Int32($0) }).reshaped([1, -1])
                generated = concatenated([generated, tokenArray], axis: 1)
            }
        } catch {
            VoxtralDebug.always("Generation failed: \(error)")
        }
        
        return generated
    }
    
    /**
     * Generate tokens from input - returns token IDs directly
     * 🚀 OPTIMIZED: Returns [Int] instead of [(MLXArray, Any?)] to avoid keeping GPU references
     * 📦 MEMORY: contextSize parameter controls KV cache limit (nil = unlimited)
     * 🔧 MEMORY: memoryOptimization parameter controls periodic eval/cleanup (aligned with flux-2-swift-mlx)
     */
    public func generateStream(
        inputIds: MLXArray,
        inputFeatures: MLXArray? = nil,
        attentionMask: MLXArray? = nil,
        maxNewTokens: Int = 100,
        temperature: Float = 1.0,
        topP: Float = 0.95,
        repetitionPenalty: Float = 1.2,
        contextSize: Int? = nil,  // nil = unlimited (KVCacheSimple), set value = limited (RotatingKVCache)
        memoryOptimization: MemoryOptimizationConfig? = nil  // nil = use VoxtralMemoryManager.shared.config
    ) throws -> [Int] {

        var tokenIds: [Int] = []

        guard inputIds.size > 0 else {
            throw VoxtralError.invalidInput("input_ids must be provided")
        }

        // Get memory optimization config (use shared manager if not provided)
        let memConfig = memoryOptimization ?? VoxtralMemoryManager.shared.config

        // Override contextSize if memory optimization specifies maxKVCacheSize
        let effectiveContextSize = contextSize ?? memConfig.maxKVCacheSize

        let stopTokens = [2, 4, 32000]

        let inputsEmbeds = mergeInputEmbeddings(inputIds: inputIds, inputFeatures: inputFeatures)

        // Python: batch_size = input_ids.shape[0]
        let batchSize = inputIds.shape[0]

        // Create KV cache - with or without size limit
        let numLayers = getLanguageModelLayerCount()
        var cache: [any KVCache]? = []

        if let maxContext = effectiveContextSize {
            // RotatingKVCache: limits memory by discarding old tokens when exceeding maxSize
            // keep: 4 = preserve first 4 tokens (BOS + critical prompt tokens)
            for _ in 0..<numLayers {
                cache!.append(RotatingKVCache(maxSize: maxContext, keep: 4))
            }
            VoxtralDebug.log("Using RotatingKVCache with maxSize=\(maxContext)")
        } else {
            // KVCacheSimple: unlimited growth (original behavior)
            for _ in 0..<numLayers {
                cache!.append(KVCacheSimple())
            }
        }

        var generated = inputIds
        var recentTokenIds: [Int] = []  // Keep only Int IDs for repetition penalty
        var currentAttentionMask = attentionMask

        // Reset memory optimization cycle counter
        VoxtralMemoryManager.shared.resetOptimizationCycle()

        for tokenIndex in 0..<maxNewTokens {
            let modelOutput: VoxtralModelOutput

            if cache![0].offset == 0 {
                modelOutput = self.callAsFunction(
                    inputIds: nil,
                    attentionMask: currentAttentionMask,
                    inputFeatures: nil,
                    inputsEmbeds: inputsEmbeds,
                    pastKeyValues: cache
                )
            } else {
                let seqLen = generated.shape[1]
                let lastToken = generated[0..., (seqLen-1)..<seqLen]
                modelOutput = self.callAsFunction(
                    inputIds: lastToken,
                    attentionMask: currentAttentionMask,
                    inputFeatures: nil,
                    inputsEmbeds: nil,
                    pastKeyValues: cache
                )
            }

            let logits = modelOutput.logits
            let seqLen = logits.shape[1]
            let lastTokenLogits = logits[0..., seqLen-1, 0...]

            var processedLogits = lastTokenLogits

            if repetitionPenalty != 1.0 && !recentTokenIds.isEmpty {
                let tokens = Array(recentTokenIds.suffix(20))
                processedLogits = applyRepetitionPenalty(logits: processedLogits, tokens: tokens, penalty: repetitionPenalty)
            }

            let nextToken = try sample(logits: processedLogits, temperature: temperature, topP: topP)

            // Extract token ID immediately to avoid keeping MLXArray references
            let currentTokenId = nextToken.squeezed().item(Int.self)
            tokenIds.append(currentTokenId)
            recentTokenIds.append(currentTokenId)

            // Python: generated = mx.concatenate([generated, next_tokens], axis=1)
            generated = concatenated([generated, nextToken.reshaped([1, 1])], axis: 1)

            // Python: if attention_mask is not None
            if currentAttentionMask != nil {
                let ones = MLXArray.ones([batchSize, 1], dtype: currentAttentionMask!.dtype)
                currentAttentionMask = concatenated([currentAttentionMask!, ones], axis: 1)
            }

            // 🔧 Apply memory optimization (aligned with flux-2-swift-mlx patterns)
            if memConfig.evalFrequency > 0 && (tokenIndex + 1) % memConfig.evalFrequency == 0 {
                // Force evaluation to prevent memory buildup from lazy computation
                eval(generated)

                if memConfig.clearCacheOnEval {
                    Memory.clearCache()
                }

                if memConfig.resetPeakMemory {
                    GPU.resetPeakMemory()
                }
            }

            // Python: if current_token_id in stop_tokens: break
            if stopTokens.contains(currentTokenId) {
                break
            }

            // Repetition detection
            if recentTokenIds.count >= 10 {
                let last10 = recentTokenIds.suffix(10)
                if last10.allSatisfy({ $0 == currentTokenId }) {
                    break
                }
            }
        }

        // 🧹 Clear KV cache and intermediate tensors
        cache = nil
        Memory.clearCache()

        return tokenIds
    }

    /**
     * Generate tokens using pre-computed audio embeddings (for hybrid Core ML + MLX mode)
     * This bypasses the audio encoder and uses embeddings computed externally (e.g., via Core ML)
     * 🔧 MEMORY: memoryOptimization parameter controls periodic eval/cleanup (aligned with flux-2-swift-mlx)
     */
    public func generateStreamWithAudioEmbeds(
        inputIds: MLXArray,
        audioEmbeds: MLXArray,
        attentionMask: MLXArray? = nil,
        maxNewTokens: Int = 100,
        temperature: Float = 1.0,
        topP: Float = 0.95,
        repetitionPenalty: Float = 1.2,
        contextSize: Int? = nil,
        memoryOptimization: MemoryOptimizationConfig? = nil  // nil = use VoxtralMemoryManager.shared.config
    ) throws -> [Int] {

        var tokenIds: [Int] = []

        guard inputIds.size > 0 else {
            throw VoxtralError.invalidInput("input_ids must be provided")
        }

        // Get memory optimization config (use shared manager if not provided)
        let memConfig = memoryOptimization ?? VoxtralMemoryManager.shared.config

        // Override contextSize if memory optimization specifies maxKVCacheSize
        let effectiveContextSize = contextSize ?? memConfig.maxKVCacheSize

        let stopTokens = [2, 4, 32000]

        // Merge token embeddings with pre-computed audio embeddings
        let inputsEmbeds = mergeInputEmbeddingsWithAudioEmbeds(inputIds: inputIds, audioEmbeds: audioEmbeds)

        let batchSize = inputIds.shape[0]

        // Create KV cache
        let numLayers = getLanguageModelLayerCount()
        var cache: [any KVCache]? = []

        if let maxContext = effectiveContextSize {
            for _ in 0..<numLayers {
                cache!.append(RotatingKVCache(maxSize: maxContext, keep: 4))
            }
            VoxtralDebug.log("Using RotatingKVCache with maxSize=\(maxContext)")
        } else {
            for _ in 0..<numLayers {
                cache!.append(KVCacheSimple())
            }
        }

        var generated = inputIds
        var recentTokenIds: [Int] = []
        var currentAttentionMask = attentionMask

        // Reset memory optimization cycle counter
        VoxtralMemoryManager.shared.resetOptimizationCycle()

        for tokenIndex in 0..<maxNewTokens {
            let modelOutput: VoxtralModelOutput

            if cache![0].offset == 0 {
                modelOutput = self.callAsFunction(
                    inputIds: nil,
                    attentionMask: currentAttentionMask,
                    inputFeatures: nil,
                    inputsEmbeds: inputsEmbeds,
                    pastKeyValues: cache
                )
            } else {
                let seqLen = generated.shape[1]
                let lastToken = generated[0..., (seqLen-1)..<seqLen]
                modelOutput = self.callAsFunction(
                    inputIds: lastToken,
                    attentionMask: currentAttentionMask,
                    inputFeatures: nil,
                    inputsEmbeds: nil,
                    pastKeyValues: cache
                )
            }

            let logits = modelOutput.logits
            let seqLen = logits.shape[1]
            let lastTokenLogits = logits[0..., seqLen-1, 0...]

            var processedLogits = lastTokenLogits

            if repetitionPenalty != 1.0 && !recentTokenIds.isEmpty {
                let tokens = Array(recentTokenIds.suffix(20))
                processedLogits = applyRepetitionPenalty(logits: processedLogits, tokens: tokens, penalty: repetitionPenalty)
            }

            let nextToken = try sample(logits: processedLogits, temperature: temperature, topP: topP)

            let currentTokenId = nextToken.squeezed().item(Int.self)
            tokenIds.append(currentTokenId)
            recentTokenIds.append(currentTokenId)

            generated = concatenated([generated, nextToken.reshaped([1, 1])], axis: 1)

            if currentAttentionMask != nil {
                let ones = MLXArray.ones([batchSize, 1], dtype: currentAttentionMask!.dtype)
                currentAttentionMask = concatenated([currentAttentionMask!, ones], axis: 1)
            }

            // 🔧 Apply memory optimization (aligned with flux-2-swift-mlx patterns)
            if memConfig.evalFrequency > 0 && (tokenIndex + 1) % memConfig.evalFrequency == 0 {
                // Force evaluation to prevent memory buildup from lazy computation
                eval(generated)

                if memConfig.clearCacheOnEval {
                    Memory.clearCache()
                }

                if memConfig.resetPeakMemory {
                    GPU.resetPeakMemory()
                }
            }

            if stopTokens.contains(currentTokenId) {
                break
            }

            if recentTokenIds.count >= 10 {
                let last10 = recentTokenIds.suffix(10)
                if last10.allSatisfy({ $0 == currentTokenId }) {
                    break
                }
            }
        }

        cache = nil
        Memory.clearCache()

        return tokenIds
    }

    /**
     * Merge input embeddings with pre-computed audio embeddings (for hybrid mode)
     */
    private func mergeInputEmbeddingsWithAudioEmbeds(
        inputIds: MLXArray,
        audioEmbeds: MLXArray
    ) -> MLXArray {
        // Get token embeddings
        var embeddings: MLXArray
        if let llamaModel = language_model as? LlamaModel {
            embeddings = llamaModel.embedTokens(inputIds)
        } else if let llamaModelWrapper = language_model as? LlamaModelWrapper {
            if let quantizedEmbedding = llamaModelWrapper.embed_tokens as? QuantizedEmbedding {
                embeddings = quantizedEmbedding(inputIds)
            } else {
                embeddings = llamaModelWrapper.embed_tokens(inputIds)
            }
        } else if let llamaStandardModel = language_model as? LlamaStandardModel {
            embeddings = llamaStandardModel.embedTokens(inputIds)
        } else {
            fatalError("Unsupported language_model type: \(type(of: language_model))")
        }

        // Create audio token mask
        let audioTokenMask = equal(inputIds, MLXArray(config.audio_token_id))

        // Same vectorized merge logic as mergeInputEmbeddings
        let numAudioTokens = audioEmbeds.shape[1]

        let audioMaskInt = audioTokenMask.asType(.int32)
        let cumAudioIdx = cumsum(audioMaskInt, axis: 1) - 1
        let audioIdxClipped = clip(cumAudioIdx, min: 0, max: numAudioTokens - 1)

        let audioEmbedsFlat = audioEmbeds.squeezed(axis: 0)
        let indicesFlat = audioIdxClipped.squeezed(axis: 0)
        let audioEmbedsGathered2D = take(audioEmbedsFlat, indicesFlat, axis: 0)
        let audioEmbedsGathered = expandedDimensions(audioEmbedsGathered2D, axis: 0)

        let maskExpanded = expandedDimensions(audioTokenMask, axis: -1)
        let finalEmbeddings = which(maskExpanded, audioEmbedsGathered, embeddings)

        eval(finalEmbeddings)

        return finalEmbeddings
    }

    // Helper function for sampling - Python equivalent
    private func sample(logits: MLXArray, temperature: Float, topP: Float) throws -> MLXArray {
        // Squeeze middle dimension if shape is [1, 1, vocab_size]
        var processedLogits = logits
        if logits.ndim == 3 && logits.shape[1] == 1 {
            processedLogits = logits.squeezed(axis: 1)  // [1, 1, vocab_size] -> [1, vocab_size]
        }
        
        // Python: if temperature == 0: return mx.argmax(logits, axis=-1, keepdims=True)
        if temperature == 0.0 {
            return argMax(processedLogits, axis: -1, keepDims: true)
        }
        
        // Python: if temperature != 1.0: logits = logits / temperature
        if temperature != 1.0 {
            processedLogits = processedLogits / temperature
        }
        
        // Python: logprobs = logits - mx.logsumexp(logits, axis=-1, keepdims=True)
        let logprobs = processedLogits - logSumExp(processedLogits, axes: [-1], keepDims: true)
        
        // Python top-p (nucleus) sampling - exact conversion from modeling_voxtral.py lines 535-552
        if topP < 1.0 {
            // Python: probs = mx.exp(logprobs)
            let probs = exp(logprobs)

            // Python: sorted_indices = mx.argsort(logprobs, axis=-1)
            let sortedIndices = argSort(logprobs, axis: -1)

            // Python: sorted_probs = mx.take_along_axis(probs, sorted_indices, axis=-1)
            let sortedProbs = takeAlong(probs, sortedIndices, axis: -1)

            // Python: cumulative_probs = mx.cumsum(sorted_probs, axis=-1)
            let cumulativeProbs = cumsum(sortedProbs, axis: -1)

            // Python: inverse_indices = mx.zeros_like(sorted_indices)
            let inverseIndices = zeros(like: sortedIndices)

            // Python: batch_indices = mx.arange(batch_size)[:, None]
            let batchIndices = MLXArray(0 ..< sortedIndices.shape[0])[0..., .newAxis]

            // Python: inverse_indices[batch_indices, sorted_indices] = mx.arange(sorted_indices.shape[-1])
            // Fix: use .last instead of [-1] for Swift Array
            let rangeValues = MLXArray(0 ..< sortedIndices.shape.last!)
            inverseIndices[batchIndices, sortedIndices] = rangeValues
            
            // Python: cumulative_probs = mx.take_along_axis(cumulative_probs, inverse_indices, axis=-1)
            let remappedCumulativeProbs = takeAlong(cumulativeProbs, inverseIndices, axis: -1)
            
            // Python: logprobs = mx.where(cumulative_probs > 1 - top_p, logprobs, -float("inf"))
            let threshold = 1.0 - topP
            let maskedLogprobs = which(
                remappedCumulativeProbs .> threshold,
                logprobs,
                -Float.infinity
            )
            
            // Python: return mx.random.categorical(logprobs)[:, None]
            let sample = categorical(maskedLogprobs, axis: -1)
            
            // Defensive check: if sample is empty, fall back to original logits
            if sample.size == 0 {
                let fallbackSample = argMax(processedLogits, axis: -1, keepDims: false)
                return expandedDimensions(fallbackSample, axes: [-1])
            }
            
            return expandedDimensions(sample, axes: [-1])
        }
        
        // Python: return mx.random.categorical(logprobs)[:, None]
        let sample = categorical(logprobs, axis: -1)
        return expandedDimensions(sample, axes: [-1])
    }
    
    // Python repetition penalty - exact conversion from modeling_voxtral.py lines 496-509
    private func applyRepetitionPenalty(logits: MLXArray, tokens: [Int], penalty: Float) -> MLXArray {
        
        if penalty == 1.0 || tokens.isEmpty {
            return logits
        }
        
        let result = logits
        let uniqueTokens = Array(Set(tokens))
        let vocabSize = logits.shape[logits.ndim - 1]  // Last dimension is vocab size
        
        
        // Python: selected_logits = logits[:, unique_tokens]
        // Apply penalty directly to each token using indexing (more efficient than take/put)
        for tokenId in uniqueTokens {
            // Defensive check: ensure tokenId is within vocab bounds
            if tokenId >= vocabSize {
                VoxtralDebug.log("⚠️ tokenId \(tokenId) >= vocabSize \(vocabSize), skipping")
                continue
            }
            
            
            // For shape [1, vocab_size], we need to index the last dimension
            // Swift: result[0..., tokenId] = Python: result[:, tokenId]
            let currentLogit = result[0..., tokenId]
            
            // Python: mx.where(selected_logits < 0, selected_logits * penalty, selected_logits / penalty)
            let penalizedLogit = which(
                currentLogit .< 0,
                currentLogit * penalty,
                currentLogit / penalty
            )
            result[0..., tokenId] = penalizedLogit
        }
        
        return result
    }
    
    // MARK: - LanguageModel Protocol Implementation
    
    /**
     * Prepare the cache state and consume the LMInput
     * Required by LanguageModel protocol
     */
    public func prepare(
        _ input: LMInput, cache: [any KVCache], state: LMOutput.State?, prefill: PrefillParameters
    ) throws -> PrepareResult {
        // For Voxtral, we need to handle both text and audio inputs
        let mergedEmbeddings: MLXArray
        
        if let audioInput = input.image?.pixels {
            // Multimodal case: merge text embeddings with audio embeddings
            mergedEmbeddings = mergeInputEmbeddings(
                inputIds: input.text.tokens,
                inputFeatures: audioInput,
                inputsEmbeds: nil
            )
        } else {
            // Text-only case: use text embeddings directly
            // Use language_model.embed_tokens instead of self.embed_tokens
            if let llamaModel = language_model as? LlamaModel {
                mergedEmbeddings = llamaModel.embedTokens(input.text.tokens)
            } else if let llamaModelWrapper = language_model as? LlamaModelWrapper {
                if let quantizedEmbedding = llamaModelWrapper.embed_tokens as? QuantizedEmbedding {
                    mergedEmbeddings = quantizedEmbedding(input.text.tokens)
                } else {
                    // Regular Embedding case
                    mergedEmbeddings = llamaModelWrapper.embed_tokens(input.text.tokens)
                }
            } else if let llamaStandardModel = language_model as? LlamaStandardModel {
                mergedEmbeddings = llamaStandardModel.embedTokens(input.text.tokens)
            } else {
                fatalError("Unsupported language_model type: \(type(of: language_model))")
            }
        }
        
        // Process through language model
        let outputs = callLanguageModel(inputs: mergedEmbeddings, mask: nil, cache: cache, inputsEmbeds: nil)
        
        // Handle both Linear and QuantizedLinear types for lm_head
        // CRITICAL: Check QuantizedLinear FIRST since it inherits from Linear!
        let logits: MLXArray
        if let quantizedLinear = lm_head as? QuantizedLinear {
            logits = quantizedLinear(outputs)
        } else if let linear = lm_head as? Linear {
            logits = linear(outputs)
        } else {
            fatalError("Unsupported lm_head type: \(type(of: lm_head))")
        }

        return .logits(LMOutput(logits: logits))
    }
    
    /**
     * Simplified interface for single token generation - override default
     */
    public func callAsFunction(_ inputs: MLXArray, cache: [any KVCache]?) -> MLXArray {
        // Process embeddings through language model
        let outputs = callLanguageModel(inputs: inputs, mask: nil, cache: cache, inputsEmbeds: nil)
        // Apply language model head to get logits
        // CRITICAL: Check QuantizedLinear FIRST since it inherits from Linear!
        let logits: MLXArray
        if let quantizedLinear = lm_head as? QuantizedLinear {
            logits = quantizedLinear(outputs)
        } else if let linear = lm_head as? Linear {
            logits = linear(outputs)
        } else {
            fatalError("Unsupported lm_head type: \(type(of: lm_head))")
        }
        return logits
    }
    
    /**
     * Sanitize weights for Voxtral model - exact Swift port of Python implementation
     * 
     * Python equivalent from mlx.voxtral:
     * https://github.com/mzbac/mlx.voxtral/blob/c3bf2175007b279ef88fedcf31fa8161bf5eee26/mlx_voxtral/modeling_voxtral.py#L715
     */
    // ✅ CLEANED UP: Removed old deprecated sanitize function - use unified one in VoxtralModelLoading.swift
}

// MARK: - KVCacheDimensionProvider Implementation

extension VoxtralForConditionalGeneration: KVCacheDimensionProvider {
    
    /**
     * Number of attention heads per layer for KV cache
     * Required by KVCacheDimensionProvider protocol
     */
    public var kvHeads: [Int] {
        // Return array with number of key-value heads for each layer
        // Each layer has textConfig.numberOfKeyValueHeads
        let numLayers = textConfig.numberOfHiddenLayers
        return Array(repeating: textConfig.numberOfKeyValueHeads, count: numLayers)
    }
}
