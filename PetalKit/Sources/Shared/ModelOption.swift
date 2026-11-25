import Foundation
#if canImport(Speech)
    import Speech
#endif

public enum ModelProvider: String, Sendable, Equatable {
    case voxtralCore = "Voxtral Core"
    case appleSpeech = "Apple Speech"
    case nvidia = "NVIDIA"
    case whisperKit = "WhisperKit"
    case mlxAudio = "MLX Audio"
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
    public let speedScore: Int
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
    case qwen3ASR17B8bit = "qwen3-asr-1.7b-8bit"
    case orukFourier2B8bit = "oruk-fourier-2b-8bit"
    case parakeetUnified06B = "parakeet-unified-en-0.6b"
    case nemotronUnified06B = "nemotron-unified-0.6b"
    case parakeetTDT06BV3 = "parakeet-tdt-0.6b-v3"
    case parakeetTDTCTC110M = "parakeet-tdt-ctc-110m"
    case whisperLargeV3Turbo = "whisper-large-v3-turbo"
    case mini3b8bit = "voxtral-realtime-4b-2602-4bit"

    private static let downloadableOptions: [Self] = [
        .parakeetTDTCTC110M, .qwen3ASR17B8bit, .orukFourier2B8bit, .parakeetUnified06B, .nemotronUnified06B,
        .parakeetTDT06BV3, .whisperLargeV3Turbo, .mini3b8bit,
    ]

    public static var allCases: [Self] {
        isAppleSpeechSupportedOnCurrentDevice ? [.appleSpeech] + downloadableOptions : downloadableOptions
    }

    public static let defaultOption: Self = .parakeetTDTCTC110M

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
        case .qwen3ASR17B8bit:
            return ModelDescriptor(
                id: rawValue,
                repoID: "mlx-community/Qwen3-ASR-1.7B-8bit",
                name: "Qwen3 ASR 1.7B",
                summary: "The most accurate open model on the Open ASR Leaderboard, with 30 languages and automatic language detection.",
                size: "~2.5 GB",
                quantization: "8-bit MLX",
                parameters: "1.7B",
                provider: .mlxAudio,
                recommended: false,
                speedScore: 3,
                smartScore: 5
            )
        case .orukFourier2B8bit:
            return ModelDescriptor(
                id: rawValue,
                repoID: "oruk/oruk-fourier-2b",
                name: "Oruk Fourier 2B",
                summary: "High-accuracy English speech recognition on Apple Silicon (noncommercial, CC BY-NC 4.0).",
                size: "~2.5 GB",
                quantization: "8-bit MLX",
                parameters: "2B",
                provider: .mlxAudio,
                recommended: false,
                speedScore: 3,
                smartScore: 5
            )
        case .parakeetUnified06B:
            return ModelDescriptor(
                id: rawValue,
                repoID: "FluidInference/parakeet-unified-en-0.6b-coreml",
                name: "Parakeet Unified 0.6B",
                summary: "Live English transcription as you speak, running locally on Apple Silicon.",
                size: "~625 MB",
                quantization: "INT8 CoreML",
                parameters: "0.6B",
                provider: .nvidia,
                recommended: false,
                speedScore: 5,
                smartScore: 3
            )
        case .nemotronUnified06B:
            return ModelDescriptor(
                id: rawValue,
                repoID: "FluidInference/nemotron-labs-unified-asr-0.6b-coreml",
                name: "Nemotron Unified 0.6B",
                summary: "NVIDIA's newest live model. It transcribes as you speak in 25 European languages, with automatic language detection.",
                size: "~1.2 GB",
                quantization: "FP16 CoreML",
                parameters: "0.6B",
                provider: .nvidia,
                recommended: false,
                speedScore: 5,
                smartScore: 4
            )
        case .parakeetTDT06BV3:
            return ModelDescriptor(
                id: rawValue,
                repoID: "FluidInference/parakeet-tdt-0.6b-v3-coreml",
                name: "Parakeet 0.6B V3",
                summary: "Fast multilingual transcription in 25 European languages, such as German, French, and Spanish, with automatic language detection.",
                size: "~485 MB",
                quantization: "INT8 CoreML",
                parameters: "0.6B",
                provider: .nvidia,
                recommended: false,
                speedScore: 5,
                smartScore: 4
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
                recommended: true,
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
        self != .appleSpeech
    }

    public var supportedTranscriptionModes: [TranscriptionMode] {
        [.verbatim]
    }

    public var supportsStreamingTranscription: Bool {
        self == .parakeetUnified06B || self == .nemotronUnified06B
    }

    public var supportsSpokenLanguageChoice: Bool {
        self == .qwen3ASR17B8bit || self == .whisperLargeV3Turbo
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

        if let option = Self(rawValue: normalized) {
            return option == .appleSpeech && !isAppleSpeechSupportedOnCurrentDevice ? .defaultOption : option
        }
        if let option = downloadableOptions.first(where: {
            $0 != .whisperLargeV3Turbo && $0.descriptor.repoID.lowercased() == normalized
        }) {
            return option
        }

        switch normalized {
        case "apple-speech-transcriber", "speechtranscriber":
            return isAppleSpeechSupportedOnCurrentDevice ? .appleSpeech : .defaultOption
        case "qwen3-asr-1.7b", "qwen3-asr-0.6b-4bit", "qwen3-asr-0.6b",
             "mlx-community/qwen3-asr-0.6b-4bit", "fluidinference/qwen3-asr-0.6b-coreml/f32",
             "fluidinference/qwen3-asr-0.6b-coreml/int8":
            return .qwen3ASR17B8bit
        case "oruk-fourier-2b", "fourier-2b":
            return .orukFourier2B8bit
        case "nemotron-unified", "nvidia/nemotron-labs-unified-asr-0.6b":
            return .nemotronUnified06B
        case "mlx-community/parakeet-tdt-0.6b-v3":
            return .parakeetTDT06BV3
        case "parakeet", "paracrete", "parakeet-tdt", "parakeet-tdt-0.6b", "parakeet-tdt-0.6b-v2",
             "fluidinference/parakeet-tdt-0.6b-v2-coreml", "parakeet-ctc", "parakeet-ctc-0.6b",
             "mlx-community/parakeet-ctc-0.6b":
            return .parakeetUnified06B
        case "parakeet-flash":
            return .parakeetTDTCTC110M
        case "whisper-large-v3-turbo-asr-fp16", "whisper-large-v3", "mlx-community/whisper-large-v3-turbo-asr-fp16",
             "whisper-tiny", "whisper-small", "openai_whisper-small_216mb", "whisper-tiny-mlx",
             "mlx-community/whisper-tiny-mlx":
            return .whisperLargeV3Turbo
        case "mini-3b", "mlx-community/voxtral-mini-3b-2507-bf16":
            return .mini3b8bit
        default:
            return .defaultOption
        }
    }
}
