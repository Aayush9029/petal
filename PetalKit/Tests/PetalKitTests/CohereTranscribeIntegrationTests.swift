import Foundation
import Testing
@testable import MLXClient

/// Integration tests for the Cohere Transcribe ONNX pipeline.
/// Requires the model to be downloaded to ~/Documents/petal/models/.
/// Skips gracefully if the model is not present.
@Suite(.serialized)
struct CohereTranscribeIntegrationTests {
    private static let modelDir = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Documents/petal/models/onnx-community/cohere-transcribe-03-2026-ONNX")

    private static var modelAvailable: Bool {
        CohereONNXCache.isModelDownloaded()
    }

    @Test
    func preprocessorExtractsMelFeatures() throws {
        // Create a simple test WAV using say CLI output
        let audioURL = try createTestAudio(text: "Hello world")
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let features = try CoherePreprocessor.extractFeatures(from: audioURL)
        #expect(features.nMels == 128)
        #expect(features.timeFrames > 0)
        #expect(features.data.count == features.nMels * features.timeFrames)
        print("Mel features: \(features.nMels) mels × \(features.timeFrames) frames")
    }

    @Test
    func tokenizerLoadsAndBuildsPrompt() throws {
        try #require(Self.modelAvailable, "Cohere model not downloaded — skipping")

        let tokenizer = try CohereTokenizer(modelDirectory: Self.modelDir)
        let prompt = tokenizer.buildPromptTokenIds(decoderStartTokenId: 13764, language: "en")

        #expect(prompt.count >= 7, "Prompt should have ≥7 tokens (startofcontext + lang + pnc + ...)")
        // First token should be <|startofcontext|> = 7
        #expect(prompt[0] == 7)
        // Second and third should be <|en|> = 62
        #expect(prompt[1] == 62)
        #expect(prompt[2] == 62)
        print("Prompt tokens: \(prompt)")
    }

    @Test
    func tokenizerDecodesTokens() throws {
        try #require(Self.modelAvailable, "Cohere model not downloaded — skipping")

        let tokenizer = try CohereTokenizer(modelDirectory: Self.modelDir)
        // Decode some regular text tokens — "hello" should decode to "hello"
        // Token 13764 is "▁" (space), which gets stripped by decode
        let decoded = tokenizer.decode(tokenIds: [13764])
        #expect(decoded.isEmpty || decoded == " " || decoded.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    @Test
    func fullTranscriptionPipeline() throws {
        try #require(Self.modelAvailable, "Cohere model not downloaded — skipping")

        let audioURL = try createTestAudio(text: "The quick brown fox jumps over the lazy dog")
        defer { try? FileManager.default.removeItem(at: audioURL) }

        print("Loading Cohere ONNX session...")
        let startLoad = CFAbsoluteTimeGetCurrent()
        let session = try CohereONNXSession(modelDirectory: Self.modelDir)
        let loadTime = CFAbsoluteTimeGetCurrent() - startLoad
        print("Session loaded in \(String(format: "%.2f", loadTime))s")

        print("Transcribing audio...")
        let startTranscribe = CFAbsoluteTimeGetCurrent()
        let transcript = try session.transcribe(audioURL: audioURL)
        let transcribeTime = CFAbsoluteTimeGetCurrent() - startTranscribe

        print("=== Transcription Result ===")
        print("Text: \"\(transcript)\"")
        print("Time: \(String(format: "%.2f", transcribeTime))s")
        print("============================")

        #expect(!transcript.isEmpty, "Transcript should not be empty")
    }

    @Test
    func shortAudioTranscription() throws {
        try #require(Self.modelAvailable, "Cohere model not downloaded — skipping")

        let audioURL = try createTestAudio(text: "Hello")
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let session = try CohereONNXSession(modelDirectory: Self.modelDir)
        let transcript = try session.transcribe(audioURL: audioURL)

        print("Short audio result: \"\(transcript)\"")
        #expect(!transcript.isEmpty)
    }

    // MARK: - Helpers

    private func createTestAudio(text: String) throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cohere_test_\(UUID().uuidString).wav")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = ["-o", outputURL.path, "--data-format=LEI16@16000", text]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "CohereTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "say command failed"])
        }
        return outputURL
    }
}
