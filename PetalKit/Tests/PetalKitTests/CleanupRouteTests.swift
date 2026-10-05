import Foundation
import Shared
import Testing
@testable import HistoryClient

@Test(arguments: [
    ("github.com", "github.com"),
    ("https://www.GitHub.com/apple/swift", "github.com"),
    ("  mail.google.com/mail/u/0  ", "mail.google.com"),
    ("localhost:3000", "localhost"),
])
func websiteInputKeepsOnlyTheHost(input: String, domain: String) {
    #expect(CleanupRoute.domain(from: input) == domain)
}

@Test(arguments: ["", "   ", "github", "https://"])
func websiteInputWithoutAHostIsRejected(input: String) {
    #expect(CleanupRoute.domain(from: input) == nil)
}

@Test
func aWebsiteRouteWinsOverItsBrowserRoute() {
    let browser = CleanupRoute(id: CleanupRoute.ID(UUID()), trigger: .app(.safari), prompt: "Browser")
    let github = CleanupRoute(id: CleanupRoute.ID(UUID()), trigger: .website("github.com"), prompt: "GitHub")
    let routes = [browser, github]

    #expect(routes.route(for: FocusedApp(app: .safari, website: "gist.github.com"))?.prompt == "GitHub")
    #expect(routes.route(for: FocusedApp(app: .safari, website: "github.com"))?.prompt == "GitHub")
    #expect(routes.route(for: FocusedApp(app: .safari, website: "notgithub.com"))?.prompt == "Browser")
    #expect(routes.route(for: FocusedApp(app: .safari))?.prompt == "Browser")
    #expect(routes.route(for: FocusedApp(app: .mail)) == nil)
    #expect(routes.route(for: nil) == nil)
}

@Test
func newRoutesStartOnAStyleThatFitsTheApp() {
    #expect(CloudPromptPreset.suggested(for: .app(.mail)) == .email)
    #expect(CloudPromptPreset.suggested(for: .app(.terminal)) == .aiPrompt)
    #expect(CloudPromptPreset.suggested(for: .app(.notes)) == .notes)
    #expect(CloudPromptPreset.suggested(for: .app(.slack)) == .cleanUp)
    #expect(CloudPromptPreset.suggested(for: .website("chatgpt.com")) == .aiPrompt)
    #expect(CloudPromptPreset.suggested(for: .website("mycompany.atlassian.net")) == .professional)
}

@Test
func minimumWordsUseALessThanLabel() {
    #expect(CleanupMinimumWords.allCases.map(\.displayName) == ["Off", "< 2 words", "< 3 words", "< 5 words", "< 10 words"])
    #expect(!CleanupMinimumWords.ten.allowsCleanup(of: "send the report to sam today please"))
    #expect(CleanupMinimumWords.ten.allowsCleanup(of: "please send the quarterly report to sam before the meeting today"))
}

@Test
func historyKeepsTheTranscriptAndTheCleanupApart() {
    let cleaned = TranscriptHistoryEntry(
        id: UUID(), timestamp: .now, modelID: "m", audioDurationSeconds: 1,
        variants: [
            TranscriptHistoryVariant(mode: "verbatim", transcriptionElapsedSeconds: 1, characterCount: 5, pasteResult: "pasted", transcriptRelativePath: "clean.txt"),
            TranscriptHistoryVariant(mode: "original", transcriptionElapsedSeconds: 1, characterCount: 9, pasteResult: "skipped", transcriptRelativePath: "raw.txt"),
        ]
    )
    #expect(cleaned.transcriptVariant?.transcriptRelativePath == "raw.txt")
    #expect(cleaned.cleanupVariant?.transcriptRelativePath == "clean.txt")

    let plain = TranscriptHistoryEntry(
        id: UUID(), timestamp: .now, modelID: "m", audioDurationSeconds: 1,
        variants: [TranscriptHistoryVariant(mode: "verbatim", transcriptionElapsedSeconds: 1, characterCount: 5, pasteResult: "pasted", transcriptRelativePath: "raw.txt")]
    )
    #expect(plain.transcriptVariant?.transcriptRelativePath == "raw.txt")
    #expect(plain.cleanupVariant == nil)
}

@Test
func historyEntriesRememberTheirApp() throws {
    let entry = TranscriptHistoryEntry(
        id: UUID(), timestamp: Date(timeIntervalSince1970: 1_000), modelID: "m", audioDurationSeconds: 1,
        app: FocusedApp(app: .safari, website: "github.com")
    )
    let decoded = try JSONDecoder().decode(TranscriptHistoryEntry.self, from: JSONEncoder().encode(entry))
    #expect(decoded.app == FocusedApp(app: .safari, website: "github.com"))

    let legacy = #"{"id":"\#(UUID().uuidString)","timestamp":0,"modelID":"m","variants":[]}"#
    #expect(try JSONDecoder().decode(TranscriptHistoryEntry.self, from: Data(legacy.utf8)).app == nil)
}

@Test
func transcribingAgainReplacesStaleVariantsAndKeepsTheApp() {
    let historyClient = HistoryClient.liveValue
    let sessionID = UUID()
    let timestamp = Date()
    func request(_ days: [TranscriptHistoryDay], mode: String, path: String, app: FocusedApp? = nil, replaces: Bool = false) -> AppendEntryRequest {
        AppendEntryRequest(
            currentDays: days, transcript: "text", modelID: "m", mode: mode, audioDuration: 1, transcriptionElapsed: 1,
            pasteResult: "pasted", audioRelativePath: nil, transcriptRelativePath: "transcripts/missing-\(sessionID)-\(path).txt",
            retentionMode: .both, timestamp: timestamp, sessionID: sessionID, app: app, replacesVariants: replaces
        )
    }

    var days = historyClient.appendEntry(request([], mode: "smart", path: "smart", app: FocusedApp(app: .mail)))
    days = historyClient.appendEntry(request(days, mode: "original", path: "original"))
    days = historyClient.appendEntry(request(days, mode: "verbatim", path: "verbatim", replaces: true))

    let entry = days.first?.entries[id: sessionID]
    #expect(entry?.variants.ids.elements == ["verbatim"])
    #expect(entry?.app == FocusedApp(app: .mail))
    #expect(entry?.cleanupVariant == nil)
}
