import Foundation
#if canImport(Speech)
    import Speech
#endif

public enum ModelProvider: String, Sendable, Equatable {
    case voxtralCore = "Voxtral Core"
    case appleSpeech = "Apple Speech"
    case fluidAudio = "FluidAudio"
    case nvidia = "NVIDIA"
    case whisperKit = "WhisperKit"
}

public struct ModelDescriptor: Sendable, Equatable {
    public let id: String
    public let repoID: String
    public let name: String
    public let summary: String
    public let size: String?
    public let quantization: String
    public let parameters: String
    public let provider: ModelProvider
    public let recommended: Bool
    /// 1–5 rating for transcription speed.
    public let speedScore: Int
    /// 1–5 rating for transcription quality/intelligence.
    public let smartScore: Int

    public init(
        id: String,
        repoID: String,
        name: String,
        summary: String,
        size: String? = nil,
        quantization: String,
        parameters: String,
        provider: ModelProvider,
        recommended: Bool,
        speedScore: Int = 3,
        smartScore: Int = 3
    ) {
        self.id = id
        self.repoID = repoID
        self.name = name
        self.summary = summary
        self.size = size
        self.quantization = quantization
        self.parameters = parameters
        self.provider = provider
        self.recommended = recommended
        self.speedScore = speedScore
        self.smartScore = smartScore
    }
}

public enum ModelOption: String, CaseIterable, Identifiable, Sendable {
    case appleSpeech = "apple-speech"
    case qwen3ASR06B4bit = "qwen3-asr-0.6b-4bit"
    case parakeetTDT06BV3 = "parakeet-tdt-0.6b-v3"
    case parakeetTDT06BV2 = "parakeet-tdt-0.6b-v2"
    case parakeetTDTCTC110M = "parakeet-tdt-ctc-110m"
    case whisperLargeV3Turbo = "whisper-large-v3-turbo"
    case whisperTiny = "whisper-tiny"
    case mini3b = "mini-3b"
    case mini3b8bit = "voxtral-realtime-4b-2602-4bit"

    public static var allCases: [ModelOption] {
        var options: [ModelOption] = [
            .qwen3ASR06B4bit,
            .parakeetTDT06BV3,
            .parakeetTDT06BV2,
            .parakeetTDTCTC110M,
            .whisperLargeV3Turbo,
            .whisperTiny,
            .mini3b,
            .mini3b8bit,
        ]
        if isAppleSpeechSupportedOnCurrentDevice {
            options.insert(.appleSpeech, at: 0)
        }
        return options
    }

    public static let defaultOption: Self = .qwen3ASR06B4bit

    public static var isAppleSpeechSupportedOnCurrentDevice: Bool {
        #if canImport(Speech)
            if #available(macOS 26, *) {
                return SpeechTranscriber.isAvailable
            }
        #endif
        return false
    }

    public var id: String {
        rawValue
    }

    public var descriptor: ModelDescriptor {
        switch self {
        case .appleSpeech:
            return ModelDescriptor(
                id: rawValue,
                repoID: "apple/speech-transcriber",
                name: "Apple Speech",
                summary: "Uses Apple's on-device Speech framework. No model download required.",
                quantization: "System",
                parameters: "On-device",
                provider: .appleSpeech,
                recommended: false,
                speedScore: 5,
                smartScore: 3
            )
        case .qwen3ASR06B4bit:
            return ModelDescriptor(
                id: rawValue,
                repoID: "FluidInference/qwen3-asr-0.6b-coreml/int8",
                name: "Qwen3 ASR 0.6B INT8",
                summary: "Memory-efficient multilingual transcription across 30 languages with automatic language detection.",
                size: "~1.3 GB",
                quantization: "INT8 CoreML",
                parameters: "0.6B",
                provider: .fluidAudio,
                recommended: true,
                speedScore: 4,
                smartScore: 4
            )
        case .parakeetTDT06BV3:
            return ModelDescriptor(
                id: rawValue,
                repoID: "FluidInference/parakeet-tdt-0.6b-v3-coreml",
                name: "Parakeet 0.6B V3",
                summary: "Top-ranked accuracy on the Open ASR Leaderboard with 110x real-time speed.",
                size: "~3.0 GB",
                quantization: "CoreML",
                parameters: "0.6B",
                provider: .nvidia,
                recommended: false,
                speedScore: 5,
                smartScore: 4
            )
        case .parakeetTDT06BV2:
            return ModelDescriptor(
                id: rawValue,
                repoID: "FluidInference/parakeet-tdt-0.6b-v2-coreml",
                name: "Parakeet 0.6B V2",
                summary: "Fastest English-only dictation, tuned for the lowest latency on Apple Silicon.",
                size: "~2.6 GB",
                quantization: "CoreML",
                parameters: "0.6B",
                provider: .nvidia,
                recommended: false,
                speedScore: 5,
                smartScore: 3
            )
        case .parakeetTDTCTC110M:
            return ModelDescriptor(
                id: rawValue,
                repoID: "FluidInference/parakeet-tdt-ctc-110m-coreml",
                name: "Parakeet 110M",
                summary: "Ultra-light hybrid TDT-CTC model with a fused encoder for near-instant English dictation.",
                size: "~455 MB",
                quantization: "CoreML",
                parameters: "110M",
                provider: .nvidia,
                recommended: false,
                speedScore: 5,
                smartScore: 2
            )
        case .whisperLargeV3Turbo:
            return ModelDescriptor(
                id: rawValue,
                repoID: "argmaxinc/whisperkit-coreml",
                name: "Whisper Large V3 Turbo",
                summary: "OpenAI's speed-optimized Whisper with near-large accuracy across 99 languages.",
                size: "~1.1 GB",
                quantization: "CoreML",
                parameters: "809M",
                provider: .whisperKit,
                recommended: false,
                speedScore: 2,
                smartScore: 5
            )
        case .whisperTiny:
            return ModelDescriptor(
                id: rawValue,
                repoID: "argmaxinc/whisperkit-coreml",
                name: "Whisper Small",
                summary: "Compact multilingual Whisper with a stronger accuracy-to-size balance than Tiny.",
                size: "~217 MB",
                quantization: "CoreML",
                parameters: "244M",
                provider: .whisperKit,
                recommended: false,
                speedScore: 3,
                smartScore: 3
            )
        case .mini3b:
            return ModelDescriptor(
                id: rawValue,
                repoID: "mlx-community/Voxtral-Mini-3B-2507-bf16",
                name: "Voxtral Mini 3B BF16",
                summary: "Mistral's speech model with transcription, Q&A, and summarization from voice.",
                size: "~9.4 GB",
                quantization: "BF16",
                parameters: "3B",
                provider: .voxtralCore,
                recommended: false,
                speedScore: 2,
                smartScore: 5
            )
        case .mini3b8bit:
            return ModelDescriptor(
                id: rawValue,
                repoID: "mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit",
                name: "Voxtral Realtime 4B",
                summary: "Mistral's latest streaming transcription model with 13-language support and sub-second delay.",
                size: "~3.2 GB",
                quantization: "4-bit MLX",
                parameters: "4B",
                provider: .voxtralCore,
                recommended: false,
                speedScore: 4,
                smartScore: 5
            )
        }
    }

    public var displayName: String {
        descriptor.name
    }

    public var summary: String {
        descriptor.summary
    }

    public var sizeLabel: String? {
        descriptor.size
    }

    public var provider: ModelProvider {
        descriptor.provider
    }

    public var providerDisplayName: String {
        descriptor.provider.rawValue
    }

    public var isRecommended: Bool {
        descriptor.recommended
    }

    public var requiresDownload: Bool {
        switch self {
        case .appleSpeech:
            return false
        case .qwen3ASR06B4bit, .parakeetTDT06BV3, .parakeetTDT06BV2, .parakeetTDTCTC110M,
             .whisperLargeV3Turbo, .whisperTiny, .mini3b, .mini3b8bit:
            return true
        }
    }

    public var supportedTranscriptionModes: [TranscriptionMode] {
        switch self {
        case .appleSpeech, .qwen3ASR06B4bit, .parakeetTDT06BV3, .parakeetTDT06BV2,
             .parakeetTDTCTC110M, .whisperLargeV3Turbo, .whisperTiny, .mini3b8bit:
            return [.verbatim]
        case .mini3b:
            return TranscriptionMode.allCases
        }
    }

    public var supportsSmartTranscription: Bool {
        supportedTranscriptionModes.contains(.smart)
    }

    public func supportsTranscriptionMode(_ mode: TranscriptionMode) -> Bool {
        supportedTranscriptionModes.contains(mode)
    }

    public static func from(modelID: String) -> Self {
        let normalized = modelID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalized {
        case Self.appleSpeech.rawValue,
             "apple-speech-transcriber",
             "speechtranscriber":
            return isAppleSpeechSupportedOnCurrentDevice ? .appleSpeech : .defaultOption
        case Self.qwen3ASR06B4bit.rawValue,
             "qwen3-asr-0.6b",
             "mlx-community/qwen3-asr-0.6b-4bit",
             "fluidinference/qwen3-asr-0.6b-coreml/f32",
             "fluidinference/qwen3-asr-0.6b-coreml/int8":
            return .qwen3ASR06B4bit
        case Self.parakeetTDT06BV3.rawValue,
             "parakeet",
             "paracrete",
             "parakeet-tdt",
             "parakeet-tdt-0.6b",
             "mlx-community/parakeet-tdt-0.6b-v3",
             "fluidinference/parakeet-tdt-0.6b-v3-coreml":
            return .parakeetTDT06BV3
        case Self.parakeetTDT06BV2.rawValue,
             "parakeet-tdt-0.6b-v2",
             "fluidinference/parakeet-tdt-0.6b-v2-coreml":
            return .parakeetTDT06BV2
        case Self.parakeetTDTCTC110M.rawValue,
             "parakeet-flash",
             "parakeet-tdt-ctc-110m",
             "fluidinference/parakeet-tdt-ctc-110m-coreml":
            return .parakeetTDTCTC110M
        case "parakeet-ctc",
             "parakeet-ctc-0.6b",
             "mlx-community/parakeet-ctc-0.6b":
            // Keep backward compatibility with old persisted IDs, but force TDT-only behavior.
            return .parakeetTDT06BV3
        case Self.whisperLargeV3Turbo.rawValue,
             "whisper-large-v3-turbo-asr-fp16",
             "whisper-large-v3",
             "mlx-community/whisper-large-v3-turbo-asr-fp16":
            return .whisperLargeV3Turbo
        case Self.whisperTiny.rawValue,
             "whisper-small",
             "openai_whisper-small_216mb",
             "whisper-tiny-mlx",
             "mlx-community/whisper-tiny-mlx":
            return .whisperTiny
        case Self.mini3b.rawValue,
             "mlx-community/voxtral-mini-3b-2507-bf16":
            return .mini3b
        case Self.mini3b8bit.rawValue,
             "mlx-community/voxtral-mini-4b-realtime-2602-4bit":
            return .mini3b8bit
        default:
            return .defaultOption
        }
    }
}
