import Dependencies
import Foundation
import Shared
import Testing
@testable import DownloadClient
@testable import MLXClient
@testable import TranscriptionClient

@Test
func unifiedUsesFluidAudioAndIsTheOnlyLiveModel() async throws {
    let model = ModelOption.parakeetUnified06B
    #expect(ModelOption.from(modelID: model.descriptor.repoID) == model)
    #expect(ModelOption.from(modelID: model.rawValue) == model)
    #expect(ModelOption.allCases.filter(\.supportsStreamingTranscription) == [model])
    try await withDependencies {
        $0.mlxClient.downloadModel = { info, _ in
            #expect(info.backend == .fluidAudio)
            #expect(info.repoId == model.descriptor.repoID)
        }
    } operation: {
        try await DownloadClient.liveValue.downloadModel(model) { _ in }
    }
}

@Test
func unifiedDownloadSelectsOneEncoderAndRequiresACompletedInventory() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    #expect(!UnifiedModelArtifacts.isDownloaded(at: directory))
    #expect(UnifiedModelArtifacts.includes("parakeet_unified_encoder_streaming_70_7_1_int8.mlmodelc/weights/weight.bin"))
    #expect(!UnifiedModelArtifacts.includes("parakeet_unified_encoder_streaming_70_13_13_int8.mlmodelc/weights/weight.bin"))
    #expect(!UnifiedModelArtifacts.includes("parakeet_unified_encoder.mlmodelc/weights/weight.bin"))

    // File inventory only; no fake CoreML models are loaded.
    for name in UnifiedModelArtifacts.requiredFiles {
        let url = directory.appendingPathComponent(name)
        if name.hasSuffix(".mlmodelc") {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try Data([1, 2, 3]).write(to: url.appendingPathComponent("weight.bin"))
        } else {
            try Data("{}".utf8).write(to: url)
        }
    }
    #expect(!UnifiedModelArtifacts.isDownloaded(at: directory))
    try UnifiedModelArtifacts.recordCompletedDownload(at: directory)
    #expect(UnifiedModelArtifacts.isDownloaded(at: directory))
    try FileManager.default.removeItem(at: directory.appendingPathComponent("vocab.json"))
    #expect(!UnifiedModelArtifacts.isDownloaded(at: directory))
}

@Test
func streamingTranscriptionBypassesFilePreprocessingAndDeliversPartials() async throws {
    let (audio, source) = AudioSampleStream.makeStream()
    source.yield([0.1, 0.2])
    source.finish()
    let transcript = try await withDependencies {
        $0.mlxClient.prepareModelIfNeeded = { model in #expect(model == .parakeetUnified06B) }
        $0.mlxClient.transcribeStream = { stream, partial in
            var received: [Float] = []
            for try await chunk in stream { received += chunk }
            #expect(received == [0.1, 0.2])
            await partial("Hello")
            return "Hello world."
        }
        // trimSilence, speedUp and whole-file transcribe remain unimplemented test dependencies.
    } operation: {
        try await TranscriptionClient.liveValue.transcribeStream(audio) { partial in
            #expect(partial == "Hello")
        }
    }
    #expect(transcript == "Hello world.")
}
