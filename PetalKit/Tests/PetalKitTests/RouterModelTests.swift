import ApplicationsClient
import CustomDump
import DependenciesTestSupport
import Foundation
import Shared
import Testing
@testable import CloudCleanupClient
@testable import CloudCleanupFeature
@testable import KeychainClient
@testable import RouterFeature

@MainActor
@Suite(.dependencies {
    $0.keychainClient = .inMemory()
    $0.uuid = .incrementing
    $0.applicationsClient.runningApplications = { [.mail, .slack, .terminal] }
    $0.applicationsClient.chooseApplication = { .notes }
})
struct RouterModelTests {
    @Test
    func `adding an open app starts it on the suggested style and selects it`() {
        let model = RouterModel(cloud: CloudCleanupModel())

        model.runningAppTapped(.mail)

        let route = try! #require(model.routes.first)
        expectNoDifference(route.trigger, .app(.mail))
        #expect(route.prompt == CloudPromptPreset.email.prompt)
        #expect(model.selection == .route(route.id))
        #expect(model.selectedStyle == .preset(.email))
    }

    @Test
    func `adding an app twice selects its route instead of adding another`() {
        let model = RouterModel(cloud: CloudCleanupModel())
        model.runningAppTapped(.terminal)
        model.fallbackTapped()

        model.runningAppTapped(.terminal)

        #expect(model.routes.count == 1)
        #expect(model.selection == .route(model.routes[0].id))
    }

    @Test(.dependencies { $0.continuousClock = TestClock() })
    func `open apps with a route are not offered again`() async {
        let model = RouterModel(cloud: CloudCleanupModel())
        let task = Task { await model.task() }
        while model.runningApps.isEmpty {
            await Task.yield()
        }
        model.runningAppTapped(.slack)

        #expect(model.addableRunningApps == [.mail, .terminal])
        task.cancel()
    }

    @Test
    func `choosing from Applications adds the chosen app`() {
        let model = RouterModel(cloud: CloudCleanupModel())

        model.chooseApplicationButtonTapped()

        expectNoDifference(model.selectedRoute?.trigger, .app(.notes))
        #expect(model.selectedStyle == .preset(.notes))
    }

    @Test
    func `a pasted address becomes a website route`() {
        let model = RouterModel(cloud: CloudCleanupModel())
        model.addRouteButtonTapped()
        #expect(model.destination == .addRoute)

        model.addRouteQuery = "https://www.GitHub.com/apple/swift"
        #expect(model.addRouteWebsite == "github.com")
        model.addRouteSubmitted()

        #expect(model.destination == nil)
        expectNoDifference(model.selectedRoute?.trigger, .website("github.com"))
        #expect(model.selectedStyle == .preset(.professional))
    }

    @Test(.dependencies { $0.continuousClock = TestClock() })
    func `typing filters open apps, and Return adds the only match`() async {
        let model = RouterModel(cloud: CloudCleanupModel())
        let task = Task { await model.task() }
        while model.runningApps.isEmpty {
            await Task.yield()
        }
        model.addRouteButtonTapped()

        model.addRouteQuery = "term"
        #expect(model.addRouteApps == [.terminal])
        #expect(model.addRouteWebsite == nil)
        model.addRouteSubmitted()

        expectNoDifference(model.selectedRoute?.trigger, .app(.terminal))
        #expect(model.destination == nil)
        task.cancel()
    }

    @Test
    func `text that is not an address adds nothing`() {
        let model = RouterModel(cloud: CloudCleanupModel())
        model.addRouteButtonTapped()
        model.addRouteQuery = "slack"

        model.addRouteSubmitted()

        #expect(model.routes.isEmpty)
        #expect(model.destination == .addRoute)
    }

    @Test
    func `a style changes only the selected route`() {
        let model = RouterModel(cloud: CloudCleanupModel())
        model.runningAppTapped(.slack)

        model.presetTapped(.professional)

        #expect(model.selectedRoute?.prompt == CloudPromptPreset.professional.prompt)
        #expect(model.sampleTranscript == CloudPromptPreset.professional.sampleTranscript)
        #expect(model.cloudSystemPrompt == CloudPromptPreset.cleanUp.prompt)
    }

    @Test
    func `As Said keeps the prompt, and a style turns cleanup back on`() {
        let model = RouterModel(cloud: CloudCleanupModel())
        model.runningAppTapped(.terminal)

        model.pasteAsSaidTapped()
        #expect(model.selectedStyle == .pasteAsSaid)
        #expect(model.selectedRoute?.action == .pasteAsSaid)
        #expect(model.selectedRoute?.prompt == CloudPromptPreset.aiPrompt.prompt)
        #expect(!model.canRunTest)

        model.presetTapped(.aiPrompt)
        #expect(model.selectedRoute?.action == .cleanUp)
    }

    @Test
    func `the fallback edits the cloud prompt for cloud models`() {
        let model = RouterModel(cloud: CloudCleanupModel())
        model.$cleanupModel.withLock { $0 = .cloud }

        model.presetTapped(.notes)

        #expect(model.cloudSystemPrompt == CloudPromptPreset.notes.prompt)
        #expect(model.smartPrompt == TranscriptionMode.defaultSmartPrompt)
    }

    @Test
    func `the fallback edits the tuned prompt for Apple Intelligence`() {
        let model = RouterModel(cloud: CloudCleanupModel())
        model.$cleanupModel.withLock { $0 = .appleIntelligence }
        #expect(model.selectedStyle == .preset(.cleanUp))

        model.presetTapped(.email)
        #expect(model.smartPrompt == CloudPromptPreset.email.prompt)
        #expect(model.cloudSystemPrompt == CloudPromptPreset.cleanUp.prompt)

        model.presetTapped(.cleanUp)
        #expect(model.smartPrompt == TranscriptionMode.defaultSmartPrompt)
    }

    @Test
    func `As Said on the fallback skips cleanup everywhere else`() {
        let model = RouterModel(cloud: CloudCleanupModel())

        model.pasteAsSaidTapped()

        #expect(model.fallbackAction == .pasteAsSaid)
        #expect(model.style(of: .fallback) == .pasteAsSaid)
    }

    @Test
    func `removing the selected route selects the fallback`() {
        let model = RouterModel(cloud: CloudCleanupModel())
        model.runningAppTapped(.mail)
        let id = model.routes[0].id

        model.removeRouteButtonTapped(id)

        #expect(model.routes.isEmpty)
        #expect(model.selection == .fallback)
    }

    @Test
    func `reset brings back the style the prompt started from`() {
        let model = RouterModel(cloud: CloudCleanupModel())
        model.runningAppTapped(.slack)
        model.presetTapped(.notes)
        model.promptChanged(CloudPromptPreset.notes.prompt + " Use bullets.")
        #expect(model.selectedStyle == .custom)
        #expect(model.canResetPrompt)

        model.resetPromptButtonTapped()

        #expect(model.selectedRoute?.prompt == CloudPromptPreset.notes.prompt)
        #expect(!model.canResetPrompt)
    }

    @Test
    func `Custom opens the editor`() {
        let model = RouterModel(cloud: CloudCleanupModel())
        model.runningAppTapped(.slack)
        model.pasteAsSaidTapped()

        model.customPromptTapped()

        #expect(model.destination == .promptEditor)
        #expect(model.selectedRoute?.action == .cleanUp)
        model.promptEditorDoneButtonTapped()
        #expect(model.destination == nil)
    }

    @Test
    func `a cloud prompt without the transcript tag shows the warning until the sentence comes back`() {
        let model = RouterModel(cloud: CloudCleanupModel())
        model.$cleanupModel.withLock { $0 = .cloud }
        model.runningAppTapped(.slack)
        model.promptChanged("Fix my words.  \n")
        #expect(model.isTranscriptTagMissing)

        model.addTranscriptTagButtonTapped()

        #expect(model.selectedRoute?.prompt == "Fix my words.\n\n\(CloudPromptTranscript.sentence)")
        #expect(!model.isTranscriptTagMissing)
    }

    @Test(.dependencies {
        $0.keychainClient = .inMemory([CloudProvider.openAI.keychainAccount: "sk-proj-live"])
        $0.cloudCleanupClient.clean = { transcript, configuration in
            CloudCleanupResult(text: "\(configuration.systemPrompt.prefix(9)): \(transcript)", model: configuration.model, elapsed: .milliseconds(900))
        }
    })
    func `a cloud test run uses the selected route's prompt`() async {
        let model = RouterModel(cloud: CloudCleanupModel())
        model.$cleanupModel.withLock { $0 = .cloud }
        model.runningAppTapped(.slack)
        model.promptChanged("Be brief.")
        model.sampleTranscript = "um hi"

        await model.runTestButtonTapped()

        expectNoDifference(model.testRun, .finished(CloudCleanupResult(text: "Be brief.: um hi", model: "gpt-6-luna", elapsed: .milliseconds(900))))
    }

    @Test
    func `a cloud test run without a key explains what is missing`() async {
        let model = RouterModel(cloud: CloudCleanupModel())
        model.$cleanupModel.withLock { $0 = .cloud }

        await model.runTestButtonTapped()

        expectNoDifference(model.testRun, .failed("Verify an API key first."))
    }

    @Test(.dependencies {
        $0.continuousClock = ImmediateClock()
        $0.foundationModelClient.refine = { transcript, prompt in "\(prompt == TranscriptionMode.defaultSmartPrompt): \(transcript)" }
    })
    func `an Apple Intelligence test run uses its tuned prompt`() async {
        let model = RouterModel(cloud: CloudCleanupModel())
        model.$cleanupModel.withLock { $0 = .appleIntelligence }
        model.sampleTranscript = "um hi"

        await model.runTestButtonTapped()

        expectNoDifference(model.testRun, .finished(CloudCleanupResult(text: "true: um hi")))
    }

    @Test(.dependencies {
        $0.keychainClient = .inMemory([CloudProvider.openAI.keychainAccount: "sk-proj-live"])
        $0.cloudCleanupClient.clean = { _, _ in throw CloudCleanupError.emptyResponse }
    })
    func `a failed test run shows the error`() async {
        let model = RouterModel(cloud: CloudCleanupModel())
        model.$cleanupModel.withLock { $0 = .cloud }

        await model.runTestButtonTapped()

        expectNoDifference(model.testRun, .failed("The model returned no text."))
    }
}

extension MacApp {
    static let mail = MacApp(bundleID: "com.apple.mail", name: "Mail")
    static let slack = MacApp(bundleID: "com.tinyspeck.slackmacgap", name: "Slack")
    static let terminal = MacApp(bundleID: "com.apple.Terminal", name: "Terminal")
    static let notes = MacApp(bundleID: "com.apple.Notes", name: "Notes")
    static let safari = MacApp(bundleID: "com.apple.Safari", name: "Safari")
}
