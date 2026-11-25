import CryptoKit
import CustomDump
import Foundation
import Shared
import Testing
@testable import DownloadClient

@Test
func appleSpeechIsReadyWithoutAnInstalledDirectory() async throws {
    let client = DownloadClient.liveValue
    #expect(client.isModelDownloaded(.appleSpeech))
    #expect(client.modelDirectoryURL(.appleSpeech) == nil)
    let updates = LockIsolated<[ModelDownloadState.Progress]>([])
    try await client.downloadModel(.appleSpeech) { update in updates.withValue { $0.append(update) } }
    expectNoDifference(updates.value, [.init(fraction: 1, statusText: "No download required for this model.")])
}

@Test(arguments: [ModelOption.qwen3ASR17B8bit, .mini3b8bit])
func partialWeightsAndMissingTokenizersDoNotMakeAnInstallationReady(model: ModelOption) throws {
    let files = try #require(SpeechModelFiles(model))
    let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    func write(_ name: String, _ contents: String = "{}") throws {
        try Data(contents.utf8).write(to: directory.appending(path: name))
    }

    try write("config.json")
    #expect(!files.isComplete(at: directory))
    try write("model-00001.safetensors")
    #expect(!files.isComplete(at: directory))
    if model == .mini3b8bit {
        try write("tekken.json")
    } else {
        try write("vocab.json")
        try write("merges.txt")
        try write("tokenizer_config.json")
    }
    #expect(files.isComplete(at: directory))

    try write("model.safetensors.index.json", #"{"weight_map":{"a":"model-00001.safetensors","b":"model-00002.safetensors"}}"#)
    #expect(!files.isComplete(at: directory))
    try write("model-00002.safetensors", "")
    #expect(!files.isComplete(at: directory))
    try write("model-00002.safetensors")
    #expect(files.isComplete(at: directory))
    try write("model-00002.safetensors.aria2")
    #expect(!files.isComplete(at: directory))
}

@Test
func fourierInstallationPinsSubfolderAndStoresRootConfigWithoutCollision() async throws {
    let files = try #require(SpeechModelFiles(.orukFourier2B8bit))
    guard case let .qwen(spec) = files else {
        Issue.record("Expected .qwen spec for .orukFourier2B8bit")
        return
    }
    #expect(spec.info.repoId == "oruk/oruk-fourier-2b")
    #expect(spec.revision == SpeechModelFiles.fourierRevision)
    #expect(spec.subfolder == "mlx/8bit")
    #expect(spec.allowedExtensions.contains("jinja"))
    #expect(spec.rootConfigReceipt == .init(
        localFileName: ".hf-root-config.json",
        expectedByteCount: 2479,
        expectedSHA256: "5bc1d99c141fc866b61efca97dcbc6412a38db25ff0934c38bf7b46fa09485a2"
    ))
    let expectedURL = try #require(SpeechModelFiles.rootConfigURL(repoID: spec.info.repoId, revision: spec.revision))
    #expect(
        expectedURL.absoluteString
            == "https://huggingface.co/oruk/oruk-fourier-2b/resolve/1c5ad7635cbdc698778eab92ae7a202c60329097/config.json?download=true"
    )

    let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let mlxConfig = #"{"quantization":{"bits":8,"group_size":64}}"#
    try Data(mlxConfig.utf8).write(to: directory.appending(path: "config.json"))
    try Data("weights".utf8).write(to: directory.appending(path: "model.safetensors"))
    try Data("{}".utf8).write(to: directory.appending(path: "tokenizer.json"))
    try Data("{}".utf8).write(to: directory.appending(path: "tokenizer_config.json"))
    #expect(!files.isComplete(at: directory))

    let rootPayload = Data(#"{"model_type":"qwen3_asr"}"#.utf8)
    let rootDigest = SHA256.hash(data: rootPayload)
        .map { byte in (byte < 16 ? "0" : "") + String(byte, radix: 16) }
        .joined()
    let testReceipt = QwenModelSpec.RootConfigReceipt(
        localFileName: SpeechModelFiles.fourierRootConfigFileName,
        expectedByteCount: rootPayload.count,
        expectedSHA256: rootDigest
    )

    await #expect(throws: DownloadClientFailure.self) {
        try await SpeechModelFiles.downloadRootConfig(
            repoID: spec.info.repoId, revision: spec.revision, to: directory, receipt: testReceipt
        ) { url in
            (rootPayload, HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!)
        }
    }
    #expect(!FileManager.default.fileExists(atPath: directory.appending(path: testReceipt.localFileName).path))

    await #expect(throws: DownloadClientFailure.self) {
        try await SpeechModelFiles.downloadRootConfig(
            repoID: spec.info.repoId, revision: spec.revision, to: directory, receipt: testReceipt
        ) { url in
            (Data("wrong".utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }
    #expect(!FileManager.default.fileExists(atPath: directory.appending(path: testReceipt.localFileName).path))

    let requestedURLs = LockIsolated<[URL]>([])
    try await SpeechModelFiles.downloadRootConfig(
        repoID: spec.info.repoId, revision: spec.revision, to: directory, receipt: testReceipt
    ) { url in
        requestedURLs.withValue { $0.append(url) }
        return (rootPayload, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    #expect(requestedURLs.value == [expectedURL])
    #expect(try String(contentsOf: directory.appending(path: "config.json"), encoding: .utf8) == mlxConfig)
    #expect(try Data(contentsOf: directory.appending(path: testReceipt.localFileName)) == rootPayload)
    #expect(files.isComplete(at: directory))

    try FileManager.default.removeItem(at: directory)
    #expect(!FileManager.default.fileExists(atPath: directory.appending(path: testReceipt.localFileName).path))
    #expect(!files.isComplete(at: directory))
}

@Test @MainActor
func speechAndCleanupTransfersFinishInOrder() async throws {
    let gate = AsyncGate()
    let events = LockIsolated<[String]>([])
    let speech = Task {
        try await ModelTransfer.speech.run(progress: { _ in }) { _ in
            events.withValue { $0.append("speech started") }
            await gate.wait()
            events.withValue { $0.append("speech finished") }
        }
    }
    await gate.waitUntilWaiting()
    let (requests, submitted) = AsyncStream<Void>.makeStream()
    let cleanup = Task {
        submitted.yield(())
        submitted.finish()
        try await ModelTransfer.cleanup.run(progress: { _ in }) { _ in
            events.withValue { $0.append("cleanup started") }
        }
    }
    for await _ in requests { break }
    await gate.open()
    try await speech.value
    try await cleanup.value
    expectNoDifference(events.value, ["speech started", "speech finished", "cleanup started"])
}
