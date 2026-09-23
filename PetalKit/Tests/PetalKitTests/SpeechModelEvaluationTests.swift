import Dependencies
import DownloadClient
import Foundation
import LogClient
import MLXClient
import Shared
import Testing
import TranscriptionClient

/// Opt-in accuracy and speed check for every speech model on synthesized speech.
/// `PETAL_TEST_ASR_EVAL=1` enables it. `PETAL_ASR_EVAL_MODELS` limits it to comma-separated model IDs.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["PETAL_TEST_ASR_EVAL"] == "1"), .serialized)
struct SpeechModelEvaluationTests {
    struct Clip: Sendable {
        let voice: String
        let language: String
        let text: String
    }

    static let englishVoices = ["Samantha", "Daniel", "Karen", "Rishi", "Tessa"]
    static let englishSentences = [
        "Please send the quarterly report to the finance team before Friday afternoon.",
        "The meeting has been moved to three thirty tomorrow in conference room B.",
        "I refactored the Python script to use async functions and it runs twice as fast now.",
        "Can you push the latest changes to the main branch and open a pull request?",
        "My flight lands at seven forty five, so I will probably be late for dinner.",
        "The new model transcribes speech on device without sending audio to the cloud.",
        "Remind me to buy milk, eggs, bread, and coffee on the way home.",
        "Our revenue grew by twelve percent compared to the same quarter last year.",
        "She said the Kubernetes cluster keeps restarting because of a memory leak.",
        "Honestly, I think we should ship the beta next week and fix the rest later.",
    ]
    static let multilingualClips = [
        Clip(voice: "Mónica", language: "es", text: "Mañana tenemos una reunión importante con el equipo de ventas."),
        Clip(voice: "Thomas", language: "fr", text: "Je voudrais réserver une table pour quatre personnes ce soir."),
        Clip(voice: "Anna", language: "de", text: "Bitte schicken Sie mir die Unterlagen bis Ende der Woche."),
    ]

    static var clips: [Clip] {
        englishVoices.flatMap { voice in
            englishSentences.map { Clip(voice: voice, language: "en", text: $0) }
        } + multilingualClips
    }

    @Test
    func evaluateSpeechModels() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "petal-asr-eval")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var audio: [(clip: Clip, url: URL, duration: Double)] = []
        for (index, clip) in Self.clips.enumerated() {
            let url = directory.appending(path: "clip-\(index).wav")
            if !FileManager.default.fileExists(atPath: url.path) {
                try synthesize(clip, to: url)
            }
            let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
            audio.append((clip, url, Double(max(size - 44, 0)) / 32_000))
        }

        let requested = ProcessInfo.processInfo.environment["PETAL_ASR_EVAL_MODELS"]?
            .split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        let models = ModelOption.allCases.filter { requested?.contains($0.rawValue) ?? true }

        var report = ["model | en WER | worst voice | multilingual WER | RTFx | failures"]
        for model in models {
            let result = try await withDependencies {
                $0.logClient.debug = { _, _ in }
                $0.logClient.error = { _, _ in }
                $0.logClient.dumpDebug = { _, _, _ in }
                $0.mlxClient = .liveValue
                $0.audioTrimClient = .liveValue
                $0.audioSpeedClient = .liveValue
            } operation: {
                try await evaluate(model, audio: audio)
            }
            report.append(result)
            print("ASR_EVAL \(result)")
        }
        print("ASR_EVAL_REPORT\n" + report.joined(separator: "\n"))
    }

    private func evaluate(_ model: ModelOption, audio: [(clip: Clip, url: URL, duration: Double)]) async throws -> String {
        let download = DownloadClient.liveValue
        if !download.isModelDownloaded(model) {
            try await download.downloadModel(model) { _ in }
        }
        let transcription = TranscriptionClient.liveValue
        try await transcription.prepareModelIfNeeded(model)

        var englishErrors = 0, englishWords = 0, multiErrors = 0, multiWords = 0, failures = 0
        var voiceErrors: [String: (Int, Int)] = [:]
        var audioSeconds = 0.0
        var elapsed = Duration.zero
        for item in audio {
            let start = ContinuousClock.now
            let text: String
            do {
                text = try await transcription.transcribe(item.url, model, .verbatim, nil)
            } catch {
                failures += 1
                continue
            }
            elapsed += ContinuousClock.now - start
            audioSeconds += item.duration
            let (errors, words) = WordErrorRate.errors(reference: item.clip.text, hypothesis: text)
            if item.clip.language == "en" {
                englishErrors += errors
                englishWords += words
                voiceErrors[item.clip.voice, default: (0, 0)].0 += errors
                voiceErrors[item.clip.voice, default: (0, 0)].1 += words
            } else {
                multiErrors += errors
                multiWords += words
                print("ASR_EVAL_ML \(model.rawValue) [\(item.clip.language)] \(text)")
            }
            if errors > 2 {
                print("ASR_EVAL_MISS \(model.rawValue) [\(item.clip.voice)] \(text)")
            }
        }
        await transcription.unloadModel()

        let worst = voiceErrors.max { Double($0.value.0) / Double($0.value.1) < Double($1.value.0) / Double($1.value.1) }
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        return [
            model.rawValue,
            percent(englishErrors, englishWords),
            worst.map { "\($0.key) \(percent($0.value.0, $0.value.1))" } ?? "-",
            percent(multiErrors, multiWords),
            String(format: "%.0fx", audioSeconds / max(seconds, 0.001)),
            "\(failures)",
        ].joined(separator: " | ")
    }

    private func percent(_ errors: Int, _ words: Int) -> String {
        words == 0 ? "-" : String(format: "%.1f%%", 100 * Double(errors) / Double(words))
    }

    private func synthesize(_ clip: Clip, to url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = ["-v", clip.voice, "-o", url.path, "--file-format=WAVE", "--data-format=LEI16@16000", clip.text]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "say failed for \(clip.voice)")
    }
}
