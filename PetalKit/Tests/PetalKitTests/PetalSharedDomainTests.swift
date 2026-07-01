import CustomDump
@testable import Shared
import Testing

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
    #expect(ModelOption.from(modelID: "qwen3-asr-1.7b") == .defaultOption)
    #expect(ModelOption.from(modelID: "Qwen/Qwen3-ASR-1.7B") == .defaultOption)
    #expect(ModelOption.from(modelID: "weiren119/Qwen3-ASR-1.7B-CoreML") == .defaultOption)
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
func modelOptionDisplayNamesUseCleanProductNames() {
    expectNoDifference(
        [
            ModelOption.appleSpeech.displayName,
            ModelOption.qwen3ASR06B4bit.displayName,
            ModelOption.parakeetTDT06BV3.displayName,
            ModelOption.parakeetTDT06BV2.displayName,
            ModelOption.parakeetTDTCTC110M.displayName,
            ModelOption.whisperTiny.displayName,
            ModelOption.whisperLargeV3Turbo.displayName,
            ModelOption.mini3b.displayName,
            ModelOption.mini3b8bit.displayName,
        ],
        [
            "Apple Speech",
            "Qwen3 ASR 0.6B",
            "Parakeet 0.6B V3",
            "Parakeet 0.6B V2",
            "Parakeet 110M",
            "Whisper Tiny",
            "Whisper Large V3 Turbo",
            "Voxtral Mini 3B BF16",
            "Voxtral Mini 3B 8-bit",
        ]
    )
}

@Test
func modelCatalogIncludesBothBackends() {
    #expect(ModelOption.allCases.contains(.mini3b))
    #expect(ModelOption.allCases.contains(.mini3b8bit))
    #expect(ModelOption.allCases.contains(.qwen3ASR06B4bit))
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
    #expect(ModelOption.qwen3ASR06B4bit.requiresDownload)
    #expect(ModelOption.qwen3ASR06B4bit.providerDisplayName == "FluidAudio")
}

@Test
func parakeetSupportsVerbatimOnly() {
    #expect(ModelOption.parakeetTDT06BV3.supportedTranscriptionModes == [.verbatim])
    #expect(!ModelOption.parakeetTDT06BV3.supportsSmartTranscription)
    #expect(ModelOption.parakeetTDT06BV3.providerDisplayName == "NVIDIA")
}

@Test
func nvidiaModelOptionsExposeDownloadSizes() {
    expectNoDifference(
        [
            ModelOption.parakeetTDT06BV3.sizeLabel,
            ModelOption.parakeetTDT06BV2.sizeLabel,
            ModelOption.parakeetTDTCTC110M.sizeLabel,
        ],
        [
            "~3.0 GB",
            "~2.6 GB",
            "~455 MB",
        ]
    )
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

@Test
func modelProviderGroupsPreserveProviderAndCatalogOrder() {
    let groups = ModelOption.providerGroups(for: [
        .qwen3ASR06B4bit,
        .parakeetTDT06BV3,
        .parakeetTDT06BV2,
        .whisperLargeV3Turbo,
        .whisperTiny,
        .mini3b,
    ])

    expectNoDifference(
        groups.map(ProviderGroupSnapshot.init),
        [
            ProviderGroupSnapshot(provider: .fluidAudio, title: "Qwen", options: [.qwen3ASR06B4bit]),
            ProviderGroupSnapshot(provider: .nvidia, title: "NVIDIA", options: [.parakeetTDT06BV3, .parakeetTDT06BV2]),
            ProviderGroupSnapshot(provider: .whisperKit, title: "Whisper", options: [.whisperLargeV3Turbo, .whisperTiny]),
            ProviderGroupSnapshot(provider: .voxtralCore, title: "Voxtral", options: [.mini3b]),
        ]
    )
    #expect(groups[id: ModelProvider.nvidia.rawValue]?.options[id: ModelOption.parakeetTDT06BV2.rawValue] == .parakeetTDT06BV2)
}

@Test
func modelProviderGroupsExcludePinnedDownloadOption() {
    let groups = ModelOption.providerGroups(
        for: [
            .qwen3ASR06B4bit,
            .parakeetTDT06BV3,
            .parakeetTDT06BV2,
            .whisperTiny,
        ],
        excluding: .parakeetTDT06BV3
    )

    expectNoDifference(
        groups.map(ProviderGroupSnapshot.init),
        [
            ProviderGroupSnapshot(provider: .fluidAudio, title: "Qwen", options: [.qwen3ASR06B4bit]),
            ProviderGroupSnapshot(provider: .nvidia, title: "NVIDIA", options: [.parakeetTDT06BV2]),
            ProviderGroupSnapshot(provider: .whisperKit, title: "Whisper", options: [.whisperTiny]),
        ]
    )
}

@Test
func modelProviderListDisplayNamesUseProductLabels() {
    expectNoDifference(
        [
            ModelProvider.appleSpeech.modelListDisplayName,
            ModelProvider.fluidAudio.modelListDisplayName,
            ModelProvider.nvidia.modelListDisplayName,
            ModelProvider.whisperKit.modelListDisplayName,
            ModelProvider.voxtralCore.modelListDisplayName,
        ],
        [
            "Built In",
            "Qwen",
            "NVIDIA",
            "Whisper",
            "Voxtral",
        ]
    )
}

private struct ProviderGroupSnapshot: Equatable {
    var provider: ModelProvider
    var title: String
    var options: [ModelOption]

    init(_ group: ModelOptionProviderGroup) {
        provider = group.provider
        title = group.title
        options = Array(group.options)
    }

    init(provider: ModelProvider, title: String, options: [ModelOption]) {
        self.provider = provider
        self.title = title
        self.options = options
    }
}
