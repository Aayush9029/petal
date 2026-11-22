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
