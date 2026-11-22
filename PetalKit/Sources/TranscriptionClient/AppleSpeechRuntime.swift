import AVFoundation
import Foundation
import Speech

@available(macOS 26, *)
enum AppleSpeechRuntime {
    static func transcribe(audioURL: URL) async throws -> String {
        guard SpeechTranscriber.isAvailable else {
            throw AppleSpeechError.unavailable
        }

        let supportedLocales = await SpeechTranscriber.supportedLocales
        let installedLocales = await SpeechTranscriber.installedLocales

        let supportedIDs = Set(supportedLocales.map(normalizedLocaleIdentifier))
        let installedSupportedLocales = installedLocales.filter { locale in
            supportedIDs.contains(normalizedLocaleIdentifier(locale))
        }

        guard !installedSupportedLocales.isEmpty else {
            throw AppleSpeechError.noInstalledLocale
        }

        let locale = preferredLocale(from: installedSupportedLocales)
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let audioFile = try AVAudioFile(forReading: audioURL)
        try await analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)

        var transcript = AttributedString()
        for try await result in transcriber.results {
            transcript += result.text
        }

        return String(transcript.characters).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func preferredLocale(from locales: [Locale]) -> Locale {
        let current = normalizedLocaleIdentifier(Locale.current)
        if let exactMatch = locales.first(where: { normalizedLocaleIdentifier($0) == current }) {
            return exactMatch
        }

        if let currentLanguage = Locale.current.language.languageCode?.identifier.lowercased(),
           let languageMatch = locales.first(where: {
               $0.language.languageCode?.identifier.lowercased() == currentLanguage
           })
        {
            return languageMatch
        }

        return locales[0]
    }

    private static func normalizedLocaleIdentifier(_ locale: Locale) -> String {
        locale.identifier
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
    }
}

enum AppleSpeechError: LocalizedError {
    case unavailable
    case noInstalledLocale

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Apple Speech is not available on this Mac."
        case .noInstalledLocale:
            "No installed Apple Speech locale is available. Add a dictation language in System Settings."
        }
    }
}
