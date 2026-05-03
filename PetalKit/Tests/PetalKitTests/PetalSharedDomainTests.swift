import Testing
@testable import Shared

@Test
func modelOptionFallbackUsesDefault() {
    #expect(ModelOption.from(modelID: "unknown-id") == .defaultOption)
}

@Test
func legacyModelIDsMapToValidatedModel() {
    #expect(ModelOption.from(modelID: "mini-3b-8bit") == .mini3b8bit)
    #expect(ModelOption.from(modelID: "mini-3b-4bit") == .mini3b8bit)
}

@Test
func qwenModelIDsMapToQwenOption() {
    #expect(ModelOption.from(modelID: "qwen3-asr-0.6b") == .qwen3ASR06B4bit)
    #expect(ModelOption.from(modelID: "mlx-community/Qwen3-ASR-0.6B-4bit") == .qwen3ASR06B4bit)
    #expect(ModelOption.from(modelID: "FluidInference/qwen3-asr-0.6b-coreml/f32") == .qwen3ASR06B4bit)
    #expect(ModelOption.from(modelID: "qwen3-asr-1.7b") == .qwen3ASR17BInt8)
    #expect(ModelOption.from(modelID: "Qwen/Qwen3-ASR-1.7B") == .qwen3ASR17BInt8)
    #expect(ModelOption.from(modelID: "weiren119/Qwen3-ASR-1.7B-CoreML") == .qwen3ASR17BInt8)
}

@Test
func parakeetModelIDsMapToParakeetOptions() {
    #expect(ModelOption.from(modelID: "parakeet") == .parakeetTDT06BV3)
    #expect(ModelOption.from(modelID: "mlx-community/parakeet-tdt-0.6b-v3") == .parakeetTDT06BV3)
    #expect(ModelOption.from(modelID: "FluidInference/parakeet-tdt-0.6b-v3-coreml") == .parakeetTDT06BV3)
    #expect(ModelOption.from(modelID: "mlx-community/parakeet-ctc-0.6b") == .parakeetTDT06BV3)
}

@Test
func whisperModelIDsMapToWhisperOptions() {
    #expect(ModelOption.from(modelID: "whisper-large-v3-turbo") == .whisperLargeV3Turbo)
    #expect(ModelOption.from(modelID: "whisper-large-v3") == .whisperLargeV3Turbo)
    #expect(ModelOption.from(modelID: "whisper-tiny") == .whisperTiny)
    #expect(ModelOption.from(modelID: "whisper-tiny-mlx") == .whisperTiny)
}

@Test
func modelOptionDescriptorMatchesRawValue() {
    for option in ModelOption.allCases {
        #expect(option.descriptor.id == option.rawValue)
    }
}

@Test
func modelCatalogIncludesBothBackends() {
    #expect(ModelOption.allCases.contains(.mini3b))
    #expect(ModelOption.allCases.contains(.mini3b8bit))
    #expect(ModelOption.allCases.contains(.qwen3ASR06B4bit))
    #expect(ModelOption.allCases.contains(.qwen3ASR17BInt8))
    #expect(ModelOption.allCases.contains(.parakeetTDT06BV3))
    #expect(ModelOption.allCases.contains(.whisperLargeV3Turbo))
}

@Test
func defaultModelRemainsRecommended() {
    #expect(ModelOption.defaultOption.isRecommended)
}

@Test
func transcriptionModeDisplayTextStable() {
    #expect(TranscriptionMode.verbatim.displayName == "Verbatim")
    #expect(TranscriptionMode.smart.displayName == "Smart")
}

@Test
func qwenSupportsVerbatimOnly() {
    #expect(ModelOption.qwen3ASR06B4bit.supportedTranscriptionModes == [.verbatim])
    #expect(!ModelOption.qwen3ASR06B4bit.supportsSmartTranscription)
    #expect(ModelOption.qwen3ASR17BInt8.supportedTranscriptionModes == [.verbatim])
    #expect(!ModelOption.qwen3ASR17BInt8.supportsSmartTranscription)
    #expect(ModelOption.qwen3ASR17BInt8.requiresDownload)
    #expect(ModelOption.qwen3ASR17BInt8.providerDisplayName == "FluidAudio")
}

@Test
func parakeetSupportsVerbatimOnly() {
    #expect(ModelOption.parakeetTDT06BV3.supportedTranscriptionModes == [.verbatim])
    #expect(!ModelOption.parakeetTDT06BV3.supportsSmartTranscription)
    #expect(ModelOption.parakeetTDT06BV3.providerDisplayName == "FluidAudio")
}

@Test
func whisperSupportsVerbatimOnly() {
    #expect(ModelOption.whisperLargeV3Turbo.supportedTranscriptionModes == [.verbatim])
    #expect(!ModelOption.whisperLargeV3Turbo.supportsSmartTranscription)
    #expect(ModelOption.whisperTiny.supportedTranscriptionModes == [.verbatim])
    #expect(!ModelOption.whisperTiny.supportsSmartTranscription)
    #expect(ModelOption.whisperLargeV3Turbo.providerDisplayName == "WhisperKit")
}

@Test
func voxtralSupportsSmartAndVerbatim() {
    #expect(ModelOption.mini3b.supportedTranscriptionModes.contains(.verbatim))
    #expect(ModelOption.mini3b.supportedTranscriptionModes.contains(.smart))
    #expect(ModelOption.mini3b.supportsSmartTranscription)
}

@Test
func appleSpeechRequiresNoDownload() {
    #expect(!ModelOption.appleSpeech.requiresDownload)
    #expect(ModelOption.appleSpeech.supportedTranscriptionModes == [.verbatim])
}

@Test
func appleSpeechVisibilityMatchesCurrentDeviceSupport() {
    #expect(
        ModelOption.allCases.contains(.appleSpeech)
            == ModelOption.isAppleSpeechSupportedOnCurrentDevice
    )
}
