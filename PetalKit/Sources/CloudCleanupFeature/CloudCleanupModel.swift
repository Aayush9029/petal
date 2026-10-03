import CloudCleanupClient
import DebugSnapshots
import Foundation
import KeychainClient
import Observation
import Shared

@DebugSnapshot
@MainActor
@Observable
public final class CloudCleanupModel {
    @CasePathable
    public enum Verification: Equatable, Sendable {
        case idle
        case verifying
        case verified
        case failed(String)
    }

    @CasePathable
    public enum ModelList: Equatable, Sendable {
        case idle
        case loading
        case loaded(IdentifiedArrayOf<CloudModel>)
        case failed(String)
    }

    @CasePathable
    public enum TestRun: Equatable, Sendable {
        case idle
        case running
        case finished(CloudCleanupResult)
        case failed(String)
    }

    @ObservationIgnored @Shared(.cloudProvider) public var provider: CloudProvider = .openAI
    @ObservationIgnored @Shared(.cloudCustomBaseURL) public var customBaseURL: String = ""
    @ObservationIgnored @Shared(.cloudSystemPrompt) public var systemPrompt: String = CloudPromptPreset.cleanUp.prompt
    @ObservationIgnored @Shared(.cloudDateTimeToolEnabled) public var dateTimeToolEnabled: Bool = false
    @ObservationIgnored @Shared(.cloudWebSearchEnabled) public var webSearchEnabled: Bool = false
    @ObservationIgnored @Shared(.cloudClipboardToolEnabled) public var clipboardToolEnabled: Bool = false
    @ObservationIgnored @Shared(.cloudSelectedTextToolEnabled) public var selectedTextToolEnabled: Bool = false
    @ObservationIgnored @Shared(.cloudModel(.openAI)) private var openAIModelID: CloudModel.ID
    @ObservationIgnored @Shared(.cloudModel(.anthropic)) private var anthropicModelID: CloudModel.ID
    @ObservationIgnored @Shared(.cloudModel(.openRouter)) private var openRouterModelID: CloudModel.ID
    @ObservationIgnored @Shared(.cloudModel(.custom)) private var customModelID: CloudModel.ID

    public var apiKey: String = "" {
        didSet {
            guard apiKey != oldValue, !verification.is(\.verifying) else { return }
            verification = .idle
        }
    }

    public var verification: Verification = .idle
    public var sampleTranscript: String = CloudPromptPreset.cleanUp.sampleTranscript
    public var testRun: TestRun = .idle
    public private(set) var savedKeys: [CloudProvider: String] = [:]
    public private(set) var modelLists: [CloudProvider: ModelList] = [:]
    public private(set) var basePreset: CloudPromptPreset?

    @ObservationIgnored @Dependency(\.cloudCleanupClient) private var cloudCleanupClient
    @ObservationIgnored @Dependency(\.keychainClient) private var keychainClient

    public init() {}

    public var modelID: CloudModel.ID {
        switch provider {
        case .openAI: openAIModelID
        case .anthropic: anthropicModelID
        case .openRouter: openRouterModelID
        case .custom: customModelID
        }
    }

    public var selectedModel: CloudModel {
        if let suggestion = provider.suggestedModels[id: modelID] {
            return suggestion
        }
        if case let .loaded(models) = modelList, let model = models[id: modelID] {
            return model
        }
        return CloudModel(id: modelID)
    }

    public var modelList: ModelList {
        modelLists[provider] ?? .idle
    }

    public var serverURLInput: String {
        get { customBaseURL }
        set {
            $customBaseURL.withLock { $0 = newValue }
            verification = .idle
            modelLists[.custom] = nil
        }
    }

    public var selectedPreset: CloudPromptPreset? {
        CloudPromptPreset.matching(systemPrompt)
    }

    public var resetPreset: CloudPromptPreset {
        selectedPreset ?? basePreset ?? .cleanUp
    }

    public func models(matching query: String) -> CloudModelSearchResults {
        let query = query.trimmed
        let needle = query.lowercased()
        func matches(_ model: CloudModel) -> Bool {
            needle.isEmpty || model.id.rawValue.lowercased().contains(needle) || model.title.lowercased().contains(needle)
        }
        let suggested = provider.suggestedModels
        var all: IdentifiedArrayOf<CloudModel> = []
        if case let .loaded(models) = modelList {
            all = IdentifiedArray(uniqueElements: models.filter { suggested[id: $0.id] == nil })
        }
        let known = suggested.ids.union(all.ids)
        let customID = CloudModel.ID(rawValue: query)
        return CloudModelSearchResults(
            suggested: suggested.filter(matches),
            all: all.filter(matches),
            customID: query.isEmpty || known.contains(customID) ? nil : customID
        )
    }

    public var hasSavedKey: Bool {
        savedKeys[provider] != nil
    }

    public var isKeyUnsaved: Bool {
        !apiKey.trimmed.isEmpty && apiKey.trimmed != savedKeys[provider]
    }

    public var isConfigured: Bool {
        guard !modelID.rawValue.trimmed.isEmpty else { return false }
        switch provider {
        case .custom: return !customBaseURL.trimmed.isEmpty
        case .openAI, .anthropic, .openRouter: return hasSavedKey
        }
    }

    public var tools: Set<CloudTool> {
        Set(CloudTool.allCases.filter { isToolEnabled($0) && isToolAvailable($0) })
    }

    public func isToolEnabled(_ tool: CloudTool) -> Bool {
        switch tool {
        case .dateTime: dateTimeToolEnabled
        case .webSearch: webSearchEnabled
        case .clipboard: clipboardToolEnabled
        case .selectedText: selectedTextToolEnabled
        }
    }

    public func isToolAvailable(_ tool: CloudTool) -> Bool {
        tool != .webSearch || provider.supportsWebSearch
    }

    public var configuration: CloudCleanupConfiguration? {
        configuration(apiKey: keychainClient.string(provider.keychainAccount) ?? "")
    }

    public func task() {
        savedKeys = Dictionary(uniqueKeysWithValues: CloudProvider.allCases.compactMap { provider in
            keychainClient.string(provider.keychainAccount).map { (provider, $0) }
        })
        apiKey = savedKeys[provider] ?? ""
    }

    public func providerTapped(_ provider: CloudProvider) {
        guard provider != self.provider else { return }
        $provider.withLock { $0 = provider }
        apiKey = savedKeys[provider] ?? ""
        verification = .idle
        testRun = .idle
    }

    public func verifyButtonTapped() async {
        let provider = provider
        let key = apiKey.trimmed
        guard !key.isEmpty || !provider.requiresAPIKey else { return }
        if provider != .custom, let owner = CloudProvider.owner(ofAPIKey: key), owner != provider {
            verification = .failed("This is an \(owner.displayName) key. Choose \(owner.displayName) above, or paste an \(provider.displayName) key.")
            return
        }

        verification = .verifying
        do {
            try await cloudCleanupClient.verifyKey(
                CloudConnection(provider: provider, apiKey: key, baseURL: customBaseURL.trimmed)
            )
            try save(key: key, for: provider)
        } catch {
            guard provider == self.provider else { return }
            verification = .failed(error.localizedDescription)
            return
        }

        guard provider == self.provider else { return }
        await loadModels(force: true)
        if provider == .custom, modelID.rawValue.trimmed.isEmpty, case let .loaded(models) = modelList, let first = models.first {
            setModelID(first.id, for: provider)
        }
        guard let configuration = configuration(apiKey: key) else {
            verification = .failed("The key works. Choose a model to finish.")
            return
        }
        do {
            try await cloudCleanupClient.checkModel(configuration)
            guard provider == self.provider else { return }
            verification = .verified
        } catch {
            guard provider == self.provider else { return }
            verification = .failed("The key works, but \(configuration.model) did not answer. \(error.localizedDescription)")
        }
    }

    public func removeKeyButtonTapped() {
        do {
            try keychainClient.delete(provider.keychainAccount)
            savedKeys[provider] = nil
            if provider.requiresAPIKey {
                modelLists[provider] = nil
            }
            apiKey = ""
            verification = .idle
        } catch {
            verification = .failed(error.localizedDescription)
        }
    }

    public func modelPickerOpened() async {
        await loadModels(force: false)
    }

    public func reloadModelsButtonTapped() async {
        await loadModels(force: true)
    }

    public func modelSelected(_ id: CloudModel.ID) {
        let id = CloudModel.ID(rawValue: id.rawValue.trimmed)
        guard !id.rawValue.isEmpty else { return }
        setModelID(id, for: provider)
        verification = .idle
        testRun = .idle
    }

    public func presetTapped(_ preset: CloudPromptPreset) {
        $systemPrompt.withLock { $0 = preset.prompt }
        basePreset = preset
        sampleTranscript = preset.sampleTranscript
        testRun = .idle
    }

    public func toolToggled(_ tool: CloudTool, isOn: Bool) {
        switch tool {
        case .dateTime: $dateTimeToolEnabled.withLock { $0 = isOn }
        case .webSearch: $webSearchEnabled.withLock { $0 = isOn }
        case .clipboard: $clipboardToolEnabled.withLock { $0 = isOn }
        case .selectedText: $selectedTextToolEnabled.withLock { $0 = isOn }
        }
    }

    public func runTestButtonTapped() async {
        let transcript = sampleTranscript.trimmed
        guard !transcript.isEmpty else { return }
        guard let configuration else {
            testRun = .failed(provider.requiresAPIKey ? "Verify an API key first." : "Enter a server URL and a model first.")
            return
        }
        testRun = .running
        do {
            testRun = .finished(try await cloudCleanupClient.clean(transcript, configuration))
        } catch {
            testRun = .failed(error.localizedDescription)
        }
    }

    private func loadModels(force: Bool) async {
        let provider = provider
        if !force, modelLists[provider]?.is(\.loaded) == true || modelLists[provider]?.is(\.loading) == true {
            return
        }
        let connection: CloudConnection
        switch provider {
        case .openAI, .anthropic:
            guard let key = savedKeys[provider] else {
                modelLists[provider] = .failed("Verify your API key to see every model.")
                return
            }
            connection = CloudConnection(provider: provider, apiKey: key)
        case .openRouter:
            connection = CloudConnection(provider: provider, apiKey: savedKeys[provider] ?? "")
        case .custom:
            guard !customBaseURL.trimmed.isEmpty else {
                modelLists[provider] = .failed("Enter a server URL to see its models.")
                return
            }
            connection = CloudConnection(provider: provider, apiKey: savedKeys[provider] ?? "", baseURL: customBaseURL.trimmed)
        }
        modelLists[provider] = .loading
        do {
            modelLists[provider] = .loaded(try await cloudCleanupClient.availableModels(connection))
        } catch {
            modelLists[provider] = .failed(error.localizedDescription)
        }
    }

    private func configuration(apiKey: String) -> CloudCleanupConfiguration? {
        let model = CloudModel.ID(rawValue: modelID.rawValue.trimmed)
        guard !model.rawValue.isEmpty, !provider.requiresAPIKey || !apiKey.isEmpty else { return nil }
        if provider == .custom, customBaseURL.trimmed.isEmpty { return nil }
        return CloudCleanupConfiguration(
            connection: CloudConnection(provider: provider, apiKey: apiKey, baseURL: customBaseURL.trimmed),
            model: model,
            systemPrompt: systemPrompt,
            tools: tools
        )
    }

    private func setModelID(_ id: CloudModel.ID, for provider: CloudProvider) {
        switch provider {
        case .openAI: $openAIModelID.withLock { $0 = id }
        case .anthropic: $anthropicModelID.withLock { $0 = id }
        case .openRouter: $openRouterModelID.withLock { $0 = id }
        case .custom: $customModelID.withLock { $0 = id }
        }
    }

    private func save(key: String, for provider: CloudProvider) throws {
        if key.isEmpty {
            try keychainClient.delete(provider.keychainAccount)
            savedKeys[provider] = nil
        } else {
            try keychainClient.setString(key, provider.keychainAccount)
            savedKeys[provider] = key
        }
    }
}

extension CloudProvider {
    var keychainAccount: KeychainClient.Account {
        KeychainClient.Account(rawValue: "cloud-api-key-\(rawValue)")
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
