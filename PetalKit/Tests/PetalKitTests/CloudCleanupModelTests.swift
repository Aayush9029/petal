import CustomDump
import DebugSnapshots
import DependenciesTestSupport
import Foundation
import Observation
import Shared
import Testing
@testable import CloudCleanupClient
@testable import CloudCleanupFeature
@testable import KeychainClient

@MainActor
@Suite(.dependencies {
    $0.keychainClient = .inMemory()
    $0.cloudCleanupClient.verifyKey = { _ in }
    $0.cloudCleanupClient.availableModels = { _ in [CloudModel(id: "gpt-6-luna"), CloudModel(id: "gpt-5.5")] }
    $0.cloudCleanupClient.checkModel = { _ in }
})
struct CloudCleanupModelTests {
    @Dependency(\.keychainClient) var keychainClient

    @Test
    func `a new model starts on Clean Up with nothing configured`() {
        let model = CloudCleanupModel()
        model.task()

        #expect(model.modelID == "gpt-6-luna")
        #expect(model.selectedPreset == .cleanUp)
        #expect(!model.isConfigured)
        #expect(model.configuration == nil)
    }

    @Test
    func `verifying checks the key and the model, then saves the key`() async {
        let model = CloudCleanupModel()
        model.apiKey = "  sk-proj-live  "

        await expect(model) {
            await model.verifyButtonTapped()
        } changes: {
            $0.verification = .verified
            $0.savedKeys[.openAI] = "sk-proj-live"
            $0.modelLists[.openAI] = .loaded([CloudModel(id: "gpt-6-luna"), CloudModel(id: "gpt-5.5")])
        }
        #expect(keychainClient.string(CloudProvider.openAI.keychainAccount) == "sk-proj-live")
        expectNoDifference(model.configuration, CloudCleanupConfiguration(
            connection: CloudConnection(provider: .openAI, apiKey: "sk-proj-live"),
            model: "gpt-6-luna",
            systemPrompt: CloudPromptPreset.cleanUp.prompt
        ))
    }

    @Test(.dependencies {
        $0.cloudCleanupClient.verifyKey = { _ in
            throw CloudCleanupError.http(status: 401, message: "Incorrect API key provided.")
        }
    })
    func `a rejected key is not saved`() async {
        let model = CloudCleanupModel()
        model.apiKey = "sk-proj-wrong"

        await expect(model) {
            await model.verifyButtonTapped()
        } changes: {
            $0.verification = .failed("Incorrect API key provided. (HTTP 401)")
        }
        #expect(keychainClient.string(CloudProvider.openAI.keychainAccount) == nil)
    }

    @Test(.dependencies {
        $0.cloudCleanupClient.checkModel = { _ in
            throw CloudCleanupError.http(status: 404, message: "The model `gpt-9` does not exist.")
        }
    })
    func `a working key with a missing model is saved and reports the model`() async {
        let model = CloudCleanupModel()
        model.modelSelected("gpt-9")
        model.apiKey = "sk-proj-live"

        await expect(model) {
            await model.verifyButtonTapped()
        } changes: {
            $0.verification = .failed("The key works, but gpt-9 did not answer. The model `gpt-9` does not exist. (HTTP 404)")
            $0.savedKeys[.openAI] = "sk-proj-live"
            $0.modelLists[.openAI] = .loaded([CloudModel(id: "gpt-6-luna"), CloudModel(id: "gpt-5.5")])
        }
    }

    @Test(arguments: [
        (CloudProvider.openAI, "sk-ant-api03-abc", "This is an Anthropic key. Choose Anthropic above, or paste an OpenAI key."),
        (.anthropic, "sk-or-v1-abc", "This is an OpenRouter key. Choose OpenRouter above, or paste an Anthropic key."),
        (.openRouter, "sk-proj-abc", "This is an OpenAI key. Choose OpenAI above, or paste an OpenRouter key."),
    ])
    func `a key for another provider fails before any request`(provider: CloudProvider, key: String, message: String) async {
        let model = withDependencies {
            $0.cloudCleanupClient.verifyKey = { _ in
                Issue.record("Sent a request for another provider's key")
            }
        } operation: {
            CloudCleanupModel()
        }
        model.providerTapped(provider)
        model.apiKey = key

        await expect(model) {
            await model.verifyButtonTapped()
        } changes: {
            $0.verification = .failed(message)
        }
    }

    @Test
    func `editing the key, the model, or the server clears the last result`() {
        let model = CloudCleanupModel()

        model.verification = .verified
        expect(model) {
            model.apiKey = "sk-proj-new"
        } changes: {
            $0.apiKey = "sk-proj-new"
            $0.verification = .idle
        }

        model.verification = .verified
        model.modelSelected("gpt-6.1-sol")
        expectNoDifference(model.verification, .idle)

        model.verification = .verified
        model.serverURLInput = "http://localhost:1234/v1"
        expectNoDifference(model.verification, .idle)
    }

    @Test
    func `a typed key that differs from the saved key is unsaved`() throws {
        try keychainClient.setString("sk-proj-saved", CloudProvider.openAI.keychainAccount)
        let model = CloudCleanupModel()
        model.task()
        #expect(model.hasSavedKey)
        #expect(!model.isKeyUnsaved)

        model.apiKey = "sk-proj-other"

        #expect(model.isKeyUnsaved)
    }

    @Test(.dependencies {
        $0.keychainClient = .inMemory([CloudProvider.anthropic.keychainAccount: "sk-ant-saved"])
    })
    func `switching providers loads that provider's key and model`() {
        let model = CloudCleanupModel()
        model.task()
        model.apiKey = "sk-proj-typed"
        model.testRun = .failed("Old")

        expect(model) {
            model.providerTapped(.anthropic)
        } changes: {
            $0.provider = .anthropic
            $0.apiKey = "sk-ant-saved"
            $0.testRun = .idle
        }
        #expect(model.modelID == "claude-opus-5-5")
        #expect(model.isConfigured)
    }

    @Test
    func `removing the key deletes it from the keychain`() throws {
        try keychainClient.setString("sk-proj-live", CloudProvider.openAI.keychainAccount)
        let model = CloudCleanupModel()
        model.task()

        expect(model) {
            model.removeKeyButtonTapped()
        } changes: {
            $0.apiKey = ""
            $0.savedKeys[.openAI] = nil
        }
        #expect(keychainClient.string(CloudProvider.openAI.keychainAccount) == nil)
    }

    @Test(.dependencies {
        $0.cloudCleanupClient.availableModels = { _ in [CloudModel(id: "llama3.2"), CloudModel(id: "qwen3:8b")] }
    })
    func `verifying a custom server lists its models and picks the first`() async {
        let model = CloudCleanupModel()
        model.providerTapped(.custom)
        model.serverURLInput = "http://localhost:11434/v1"

        await expect(model) {
            await model.verifyButtonTapped()
        } changes: {
            $0.verification = .verified
            $0.modelLists[.custom] = .loaded([CloudModel(id: "llama3.2"), CloudModel(id: "qwen3:8b")])
        }
        #expect(model.modelID == "llama3.2")
        #expect(model.isConfigured)
        expectNoDifference(model.configuration?.connection, CloudConnection(provider: .custom, baseURL: "http://localhost:11434/v1"))
    }

    @Test
    func `opening the picker loads the provider's models once`() async throws {
        try keychainClient.setString("sk-proj-live", CloudProvider.openAI.keychainAccount)
        let model = CloudCleanupModel()
        model.task()

        await expect(model) {
            await model.modelPickerOpened()
        } changes: {
            $0.modelLists[.openAI] = .loaded([CloudModel(id: "gpt-6-luna"), CloudModel(id: "gpt-5.5")])
        }
        await expect(model) {
            await model.modelPickerOpened()
        } changes: { _ in }
    }

    @Test
    func `the picker explains when a key is needed to list models`() async {
        let model = CloudCleanupModel()

        await expect(model) {
            await model.modelPickerOpened()
        } changes: {
            $0.modelLists[.openAI] = .failed("Verify your API key to see every model.")
        }
    }

    @Test(.dependencies {
        $0.cloudCleanupClient.availableModels = { _ in
            [CloudModel(id: "openai/gpt-6-luna", name: "OpenAI: GPT-6 Luna"), CloudModel(id: "mistralai/mistral-small-2603", name: "Mistral: Small")]
        }
    })
    func `searching filters suggestions and loaded models and offers a custom ID`() async {
        let model = CloudCleanupModel()
        model.providerTapped(.openRouter)
        await model.modelPickerOpened()

        expectNoDifference(model.models(matching: "mistral"), CloudModelSearchResults(
            all: [CloudModel(id: "mistralai/mistral-small-2603", name: "Mistral: Small")],
            customID: "mistral"
        ))
        expectNoDifference(model.models(matching: "openai/gpt-6-luna").customID, nil)
        #expect(model.models(matching: "").suggested == CloudProvider.openRouter.suggestedModels)

        model.modelSelected("my-org/fine-tune")
        #expect(model.modelID == "my-org/fine-tune")
        #expect(model.selectedModel == CloudModel(id: "my-org/fine-tune"))
    }

    @Test
    func `selecting a model notifies the view`() {
        let model = CloudCleanupModel()
        let changed = LockIsolated(false)
        withObservationTracking {
            _ = model.selectedModel
        } onChange: {
            changed.setValue(true)
        }

        model.modelSelected("gpt-6.1-sol")

        #expect(changed.value)
        #expect(model.selectedModel == CloudModel(id: "gpt-6.1-sol", name: "GPT-6.1 Sol", note: "Balanced"))
    }

    @Test
    func `presets replace the prompt and the sample`() {
        let model = CloudCleanupModel()

        expect(model) {
            model.presetTapped(.email)
        } changes: {
            $0.systemPrompt = CloudPromptPreset.email.prompt
            $0.sampleTranscript = CloudPromptPreset.email.sampleTranscript
            $0.basePreset = .email
        }
        #expect(model.selectedPreset == .email)

        model.$systemPrompt.withLock { $0 += "\nSign every email as Jo." }
        #expect(model.selectedPreset == nil)
        #expect(model.resetPreset == .email)
    }

    @Test
    func `tools follow the toggles and the provider`() {
        let model = CloudCleanupModel()
        for tool in CloudTool.allCases {
            model.toolToggled(tool, isOn: true)
        }
        #expect(model.tools == [.dateTime, .webSearch, .clipboard, .selectedText])

        model.providerTapped(.custom)
        #expect(model.tools == [.dateTime, .clipboard, .selectedText])
        #expect(!model.isToolAvailable(.webSearch))
    }

    @Test(.dependencies {
        $0.keychainClient = .inMemory([CloudProvider.openAI.keychainAccount: "sk-proj-live"])
        $0.cloudCleanupClient.clean = { transcript, configuration in
            CloudCleanupResult(text: "Cleaned: \(transcript)", model: configuration.model, elapsed: .milliseconds(900))
        }
    })
    func `a test run shows the cleaned sample`() async {
        let model = CloudCleanupModel()
        model.sampleTranscript = "um hi"

        await expect(model) {
            await model.runTestButtonTapped()
        } changes: {
            $0.testRun = .finished(CloudCleanupResult(text: "Cleaned: um hi", model: "gpt-6-luna", elapsed: .milliseconds(900)))
        }
    }

    @Test
    func `a test run without a key explains what is missing`() async {
        let model = CloudCleanupModel()

        await expect(model) {
            await model.runTestButtonTapped()
        } changes: {
            $0.testRun = .failed("Verify an API key first.")
        }
    }

    @Test(.dependencies {
        $0.keychainClient = .inMemory([CloudProvider.openAI.keychainAccount: "sk-proj-live"])
        $0.cloudCleanupClient.clean = { _, _ in throw CloudCleanupError.emptyResponse }
    })
    func `a failed test run shows the error`() async {
        let model = CloudCleanupModel()

        await expect(model) {
            await model.runTestButtonTapped()
        } changes: {
            $0.testRun = .failed("The model returned no text.")
        }
    }
}
