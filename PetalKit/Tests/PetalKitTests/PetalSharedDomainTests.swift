import Foundation
import Shared
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
func orukFourierModelIDsAndMetadata() {
    #expect(ModelOption.defaultOption == .parakeetTDTCTC110M)
    #expect(ModelOption.from(modelID: "oruk-fourier-2b-8bit") == .orukFourier2B8bit)
    #expect(ModelOption.from(modelID: "oruk-fourier-2b") == .orukFourier2B8bit)
    #expect(ModelOption.from(modelID: "fourier-2b") == .orukFourier2B8bit)
    #expect(ModelOption.from(modelID: "oruk/oruk-fourier-2b") == .orukFourier2B8bit)

    let descriptor = ModelOption.orukFourier2B8bit.descriptor
    #expect(descriptor.repoID == "oruk/oruk-fourier-2b")
    #expect(descriptor.provider == .mlxAudio)
    #expect(!descriptor.recommended)
    #expect(!ModelOption.orukFourier2B8bit.supportsSpokenLanguageChoice)
    #expect(!ModelOption.orukFourier2B8bit.supportsStreamingTranscription)
    #expect(descriptor.summary.contains("English"))
    #expect(descriptor.summary.contains("CC BY-NC 4.0"))
}

@Test
func parakeetModelIDsMapToTheirCurrentModels() {
    #expect(ModelOption.from(modelID: "parakeet") == .parakeetUnified06B)
    #expect(ModelOption.from(modelID: "parakeet-tdt-0.6b-v2") == .parakeetUnified06B)
    #expect(ModelOption.from(modelID: "mlx-community/parakeet-ctc-0.6b") == .parakeetUnified06B)
    #expect(ModelOption.from(modelID: "parakeet-tdt-0.6b-v3") == .parakeetTDT06BV3)
    #expect(ModelOption.from(modelID: "FluidInference/parakeet-tdt-0.6b-v3-coreml") == .parakeetTDT06BV3)
    #expect(ModelOption.from(modelID: "mlx-community/parakeet-tdt-0.6b-v3") == .parakeetTDT06BV3)
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
func raycastCanReadThePublishedModelCatalog() throws {
    let catalog = ModelCatalogEntry.catalog { $0 == .parakeetTDTCTC110M }
    let data = try JSONEncoder().encode(catalog)
    let rows = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    for row in rows {
        for key in ["id", "name", "summary", "provider"] {
            let field = try #require(row[key] as? String)
            #expect(!field.isEmpty)
        }
    }
    let downloaded = try #require(rows.first { $0["id"] as? String == "parakeet-tdt-ctc-110m" })
    #expect(downloaded["isDownloaded"] as? Bool == true)
    #expect(downloaded["isRecommended"] as? Bool == true)
    #expect(downloaded["size"] is String)
    let stream = try #require(rows.first { $0["id"] as? String == "parakeet-unified-en-0.6b" })
    #expect(stream["supportsLiveTranscription"] as? Bool == true)
    #expect(stream["isDownloaded"] as? Bool == false)
}

@Test
func legacyHistoryKeepsItsTranscriptWhenWrittenForRaycast() throws {
    let legacy = """
        [{"day":"2024-02-01","entries":[{
          "id":"49238B72-0017-41BD-966C-E63E80933BEC","timestamp":15,"modelID":"legacy-model",
          "transcript":"Hi.","transcriptRelativePath":"transcripts/entry.txt","pasteResult":"pasted"
        }]}]
        """
    let days = try JSONDecoder().decode([TranscriptHistoryDay].self, from: Data(legacy.utf8))
    let data = try JSONEncoder().encode(days)
    let rows = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    let day = try #require(rows.first)
    #expect(day["day"] as? String == "2024-02-01")
    let entries = try #require(day["entries"] as? [[String: Any]])
    let entry = try #require(entries.first)
    #expect(entry["id"] as? String == "49238B72-0017-41BD-966C-E63E80933BEC")
    #expect(entry["modelID"] as? String == "legacy-model")
    #expect(entry["timestamp"] as? Double == 15)
    let variants = try #require(entry["variants"] as? [[String: Any]])
    let variant = try #require(variants.first)
    #expect(variant["mode"] as? String == "verbatim")
    #expect(variant["characterCount"] as? Int == 3)
    #expect(variant["pasteResult"] as? String == "pasted")
    #expect(variant["transcriptRelativePath"] as? String == "transcripts/entry.txt")
}
