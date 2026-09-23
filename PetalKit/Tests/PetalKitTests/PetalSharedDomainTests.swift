import CustomDump
@testable import Shared
import Testing

@Test
func modelOptionFallbackUsesDefault() {
    #expect(ModelOption.from(modelID: "unknown-id") == .defaultOption)
}

@Test
func removedVoxtralModelIDsFallBackToDefault() {
    #expect(ModelOption.from(modelID: "mini-3b-8bit") == .defaultOption)
    #expect(ModelOption.from(modelID: "mini-3b-4bit") == .defaultOption)
}

@Test
func qwenModelIDsMapToQwen17B() {
    #expect(ModelOption.from(modelID: "qwen3-asr-1.7b-8bit") == .qwen3ASR17B8bit)
    #expect(ModelOption.from(modelID: "mlx-community/Qwen3-ASR-1.7B-8bit") == .qwen3ASR17B8bit)
    #expect(ModelOption.from(modelID: "qwen3-asr-0.6b-4bit") == .qwen3ASR17B8bit)
    #expect(ModelOption.from(modelID: "FluidInference/qwen3-asr-0.6b-coreml/int8") == .qwen3ASR17B8bit)
    #expect(ModelOption.from(modelID: "weiren119/Qwen3-ASR-1.7B-CoreML") == .defaultOption)
}

@Test
func parakeetTDTModelIDsMapToParakeetUnified() {
    #expect(ModelOption.from(modelID: "parakeet") == .parakeetUnified06B)
    #expect(ModelOption.from(modelID: "parakeet-tdt-0.6b-v3") == .parakeetUnified06B)
    #expect(ModelOption.from(modelID: "parakeet-tdt-0.6b-v2") == .parakeetUnified06B)
    #expect(ModelOption.from(modelID: "FluidInference/parakeet-tdt-0.6b-v3-coreml") == .parakeetUnified06B)
    #expect(ModelOption.from(modelID: "mlx-community/parakeet-ctc-0.6b") == .parakeetUnified06B)
    #expect(ModelOption.from(modelID: "parakeet-tdt-ctc-110m") == .parakeetTDTCTC110M)
}

@Test
func whisperModelIDsMapToLargeV3Turbo() {
    #expect(ModelOption.from(modelID: "whisper-large-v3-turbo") == .whisperLargeV3Turbo)
    #expect(ModelOption.from(modelID: "whisper-large-v3") == .whisperLargeV3Turbo)
    #expect(ModelOption.from(modelID: "whisper-tiny") == .whisperLargeV3Turbo)
    #expect(ModelOption.from(modelID: "whisper-small") == .whisperLargeV3Turbo)
    #expect(ModelOption.from(modelID: "openai_whisper-small_216MB") == .whisperLargeV3Turbo)
}

@Test
func voxtralModelIDsMapToRealtimeOption() {
    #expect(ModelOption.from(modelID: "mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit") == .mini3b8bit)
    #expect(ModelOption.from(modelID: "mini-3b") == .mini3b8bit)
    #expect(ModelOption.from(modelID: "mlx-community/Voxtral-Mini-3B-2507-bf16") == .mini3b8bit)
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
            ModelOption.qwen3ASR17B8bit.displayName,
            ModelOption.parakeetUnified06B.displayName,
            ModelOption.parakeetTDTCTC110M.displayName,
            ModelOption.whisperLargeV3Turbo.displayName,
            ModelOption.mini3b8bit.displayName,
        ],
        [
            "Apple Speech",
            "Qwen3 ASR 1.7B",
            "Parakeet Unified 0.6B",
            "Parakeet 110M",
            "Whisper Large V3 Turbo",
            "Voxtral Realtime 4B",
        ]
    )
}

@Test
func modelCatalogHasOneModelPerFamily() {
    #expect(ModelOption.allCases.filter { $0 != .appleSpeech } == [
        .parakeetTDTCTC110M,
        .qwen3ASR17B8bit,
        .parakeetUnified06B,
        .whisperLargeV3Turbo,
        .mini3b8bit,
    ])
}

@Test
func parakeet110MIsTheOnlyRecommendedDefaultModel() {
    #expect(ModelOption.defaultOption == .parakeetTDTCTC110M)
    #expect(ModelOption.defaultOption.isRecommended)
    #expect(ModelOption.allCases.filter(\.isRecommended) == [.parakeetTDTCTC110M])
    #expect(ModelOption.allCases.first(where: \.requiresDownload) == .parakeetTDTCTC110M)
}

@Test
func transcriptionModeDisplayTextStable() {
    #expect(TranscriptionMode.verbatim.displayName == "Verbatim")
    #expect(TranscriptionMode.smart.displayName == "Smart")
}

@Test
func speechModelsSupportVerbatimOnly() {
    for option in ModelOption.allCases {
        #expect(option.supportedTranscriptionModes == [.verbatim])
        #expect(!option.supportsSmartTranscription)
    }
}

@Test
func providerLabels() {
    #expect(ModelOption.qwen3ASR17B8bit.providerDisplayName == "MLX Audio")
    #expect(ModelOption.parakeetUnified06B.providerDisplayName == "NVIDIA")
    #expect(ModelOption.whisperLargeV3Turbo.providerDisplayName == "WhisperKit")
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
        .parakeetTDTCTC110M,
        .qwen3ASR17B8bit,
        .parakeetUnified06B,
        .whisperLargeV3Turbo,
        .mini3b8bit,
    ])

    expectNoDifference(
        groups.map(ProviderGroupSnapshot.init),
        [
            ProviderGroupSnapshot(provider: .nvidia, title: "NVIDIA", options: [.parakeetTDTCTC110M, .parakeetUnified06B]),
            ProviderGroupSnapshot(provider: .mlxAudio, title: "Qwen", options: [.qwen3ASR17B8bit]),
            ProviderGroupSnapshot(provider: .whisperKit, title: "Whisper", options: [.whisperLargeV3Turbo]),
            ProviderGroupSnapshot(provider: .voxtralCore, title: "Voxtral", options: [.mini3b8bit]),
        ]
    )
}

@Test
func modelProviderGroupsExcludePinnedDownloadOption() {
    let groups = ModelOption.providerGroups(
        for: [.parakeetTDTCTC110M, .qwen3ASR17B8bit, .parakeetUnified06B],
        excluding: .parakeetUnified06B
    )

    expectNoDifference(
        groups.map(ProviderGroupSnapshot.init),
        [
            ProviderGroupSnapshot(provider: .nvidia, title: "NVIDIA", options: [.parakeetTDTCTC110M]),
            ProviderGroupSnapshot(provider: .mlxAudio, title: "Qwen", options: [.qwen3ASR17B8bit]),
        ]
    )
}

@Test
func modelProviderListDisplayNamesUseProductLabels() {
    expectNoDifference(
        [
            ModelProvider.appleSpeech.modelListDisplayName,
            ModelProvider.mlxAudio.modelListDisplayName,
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
