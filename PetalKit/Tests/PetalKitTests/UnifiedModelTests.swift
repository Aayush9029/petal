import Dependencies
import Foundation
import Shared
import Testing
@testable import DownloadClient
@testable import MLXClient
@testable import TranscriptionClient

@Test
func unifiedDownloadSelectsOneEncoderAndRequiresACompletedInventory() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    #expect(!UnifiedModelArtifacts.parakeet.isDownloaded(at: directory))
    #expect(UnifiedModelArtifacts.parakeet.includes("parakeet_unified_encoder_streaming_70_7_1_int8.mlmodelc/weights/weight.bin"))
    #expect(!UnifiedModelArtifacts.parakeet.includes("parakeet_unified_encoder_streaming_70_13_13_int8.mlmodelc/weights/weight.bin"))
    #expect(!UnifiedModelArtifacts.parakeet.includes("parakeet_unified_encoder.mlmodelc/weights/weight.bin"))

    for name in UnifiedModelArtifacts.parakeet.requiredFiles {
        let url = directory.appendingPathComponent(name)
        if name.hasSuffix(".mlmodelc") {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try Data([1, 2, 3]).write(to: url.appendingPathComponent("weight.bin"))
        } else {
            try Data("{}".utf8).write(to: url)
        }
    }
    #expect(!UnifiedModelArtifacts.parakeet.isDownloaded(at: directory))
    try UnifiedModelArtifacts.parakeet.recordCompletedDownload(at: directory)
    #expect(UnifiedModelArtifacts.parakeet.isDownloaded(at: directory))
    try FileManager.default.removeItem(at: directory.appendingPathComponent("vocab.json"))
    #expect(!UnifiedModelArtifacts.parakeet.isDownloaded(at: directory))
}

@Test
func streamingTranscriptionBypassesFilePreprocessingAndDeliversPartials() async throws {
    let (audio, source) = AudioSampleStream.makeStream()
    source.yield([0.1, 0.2])
    source.finish()
    let partials = LockIsolated<[String]>([])
    let transcript = try await withDependencies {
        $0.mlxClient.transcribeStream = { stream, model, partial in
            #expect(model == .parakeetUnified06B)
            var received: [Float] = []
            for try await chunk in stream { received += chunk }
            #expect(received == [0.1, 0.2])
            await partial("Hello")
            return "Hello world."
        }
    } operation: {
        try await TranscriptionClient.liveValue.transcribeStream(audio, .parakeetUnified06B) { partial in
            partials.withValue { $0.append(partial) }
        }
    }
    #expect(partials.value == ["Hello"])
    #expect(transcript == "Hello world.")
}

@Test
func nemotronUnifiedDownloadsOneFP16EncoderFromTheCoreMLFolder() throws {
    let model = ModelOption.nemotronUnified06B
    let artifacts = UnifiedModelArtifacts.nemotron
    #expect(ModelOption.from(modelID: model.descriptor.repoID) == model)
    #expect(ModelOption.from(modelID: "nvidia/nemotron-labs-unified-asr-0.6b") == model)
    #expect(model.supportsStreamingTranscription)
    #expect(artifacts.subfolder == "coreml")
    #expect(artifacts.directory.lastPathComponent == "coreml")
    #expect(artifacts.includes("nemotron_unified_encoder_streaming_70_7_7.mlmodelc/weights/weight.bin"))
    #expect(!artifacts.includes("nemotron_unified_encoder_streaming_70_7_7_int8.mlmodelc/weights/weight.bin"))
    #expect(!artifacts.includes("nemotron_unified_encoder_streaming_70_13_13.mlmodelc/weights/weight.bin"))
    #expect(!artifacts.includes("nemotron_unified_encoder.mlmodelc/weights/weight.bin"))
    #expect(!artifacts.includes("nemotron_unified_decoder.mlpackage/Manifest.json"))

}

@Test
func streamingRejectsAModelWithoutLiveSupport() async {
    let (audio, source) = AudioSampleStream.makeStream()
    source.finish()
    await #expect(throws: (any Error).self) {
        try await TranscriptionClient.liveValue.transcribeStream(audio, .parakeetTDTCTC110M) { _ in }
    }
}
