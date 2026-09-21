import AppKit
import AudioClient
import Dependencies
import FloatingCapsuleClient
import Foundation
import LogClient
import MLXClient
import Shared
import Testing
import TranscriptionClient

/// Opt-in app-client integration using real speech and CoreML weights, without a microphone or paste.
@Test(.enabled(if: ProcessInfo.processInfo.environment["PETAL_TEST_UNIFIED_STREAMING"] == "1"))
@MainActor
func realUnifiedStreamsThroughCaptureAndFlushesBeforeReturning() async throws {
    try await withDependencies {
        $0.logClient.debug = { _, _ in }
    } operation: {
        try await runUnifiedStreamingIntegration()
    }
}

@MainActor
private func runUnifiedStreamingIntegration() async throws {
    let fixture = try #require(ProcessInfo.processInfo.environment["PETAL_E2E_AUDIO_FILE"])
    #expect(FileManager.default.fileExists(atPath: fixture))
    _ = NSApplication.shared
    let modelClient = MLXClient.liveValue
    try await modelClient.prepareModelIfNeeded(.parakeetUnified06B)
    let capsule = FloatingCapsuleClient.liveValue
    let audioClient = AudioClient.liveValue
    let updates = PartialTranscripts()
    await capsule.showRecording({}, {})
    let audio = try await audioClient.startStreamingRecording { _ in }
    let task = Task {
        try await withDependencies {
            $0.mlxClient = modelClient
        } operation: {
            try await TranscriptionClient.liveValue.transcribeStream(audio) { text in
                await updates.append(text)
                await capsule.updateLiveTranscript(text)
            }
        }
    }
    do {
        // The fixture is delivered in real time by the production capture client.
        try await Task.sleep(for: .seconds(8))
        #expect(await updates.count > 1, "Partials must arrive before recording stops")
        if let path = ProcessInfo.processInfo.environment["PETAL_STREAMING_SCREENSHOT_PATH"] {
            let view = try #require(NSApp.windows.first(where: {
                $0 is NSPanel && $0.frame.size == NSSize(width: 400, height: 178)
            })?.contentView)
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: path))
        }
        let recording = try await audioClient.stopRecording()
        defer { try? FileManager.default.removeItem(at: recording) }
        await capsule.showTranscribing()
        let text = try await task.value
        let first = await updates.first ?? ""
        #expect(!text.isEmpty)
        #expect(text.hasPrefix(first))
        print("Petal Unified integration: \(await updates.count) partials; final: \(text)")
    } catch {
        task.cancel()
        await audioClient.cancelRecording()
        _ = await task.result
        await capsule.hide()
        throw error
    }
    await capsule.hide()
}

private actor PartialTranscripts {
    private var texts: [String] = []
    var count: Int { texts.count }
    var first: String? { texts.first }
    func append(_ text: String) { texts.append(text) }
}
