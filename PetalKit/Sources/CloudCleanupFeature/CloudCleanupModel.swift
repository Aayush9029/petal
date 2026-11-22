import CloudCleanupClient
import DebugSnapshots
import Foundation
import KeychainClient
import Observation
import PermissionsClient
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

    @ObservationIgnored @Shared(.cloudProvider) public var provider: CloudProvider
    @ObservationIgnored @Shared(.cloudCustomBaseURL) public var customBaseURL: String
    @ObservationIgnored @Shared(.cloudSystemPrompt) public var systemPrompt: String
    @ObservationIgnored @Shared(.cloudDateTimeToolEnabled) public var dateTimeToolEnabled: Bool
    @ObservationIgnored @Shared(.cloudWebSearchEnabled) public var webSearchEnabled: Bool
    @ObservationIgnored @Shared(.cloudClipboardToolEnabled) public var clipboardToolEnabled: Bool
    @ObservationIgnored @Shared(.cloudSelectedTextToolEnabled) public var selectedTextToolEnabled: Bool
    @ObservationIgnored @Shared(.cloudScreenToolEnabled) public var screenToolEnabled: Bool
    @ObservationIgnored @Shared(.cloudModel(.openAI)) private var openAIModelID: CloudModel.ID
    @ObservationIgnored @Shared(.cloudModel(.anthropic)) private var anthropicModelID: CloudModel.ID
    @ObservationIgnored @Shared(.cloudModel(.openRouter)) private var openRouterModelID: CloudModel.ID
    @ObservationIgnored @Shared(.cloudModel(.custom)) private var customModelID: CloudModel.ID

    public var apiKey: String = "" {
        didSet {
            guard apiKey != oldValue else { return }
            verification = .idle
        }
    }

    public var verification: Verification = .idle {
        didSet { verificationRevision += 1 }
    }
    @ObservationIgnored @DebugSnapshotIgnored private var verificationRevision = 0
    @ObservationIgnored @DebugSnapshotIgnored private var catalogRevisions: [CloudProvider: Int] = [:]
    public private(set) var savedKeys: [CloudProvider: String] = [:]
    public private(set) var modelLists: [CloudProvider: ModelList] = [:]
    public private(set) var hasScreenRecordingPermission = false

    @ObservationIgnored @Dependency(\.cloudCleanupClient) private var cloudCleanupClient
    @ObservationIgnored @Dependency(\.keychainClient) private var keychainClient
    @ObservationIgnored @Dependency(\.permissionsClient) private var permissionsClient
    @ObservationIgnored @Dependency(\.continuousClock) private var clock

    public init() {}

    public var modelID: CloudModel.ID {
        modelSelection.wrappedValue
    }

    private var modelSelection: Shared<CloudModel.ID> {
        switch provider {
        case .openAI: $openAIModelID
        case .anthropic: $anthropicModelID
        case .openRouter: $openRouterModelID
        case .custom: $customModelID
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
        configuration(apiKey: savedKeys[provider] ?? "") != nil
    }

    public var tools: Set<CloudTool> {
        Set(CloudTool.allCases.filter { isToolEnabled($0) && isToolAvailable($0) })
    }

    public func isToolEnabled(_ tool: CloudTool) -> Bool {
        setting(for: tool).wrappedValue
    }

    private func setting(for tool: CloudTool) -> Shared<Bool> {
        switch tool {
        case .dateTime: $dateTimeToolEnabled
        case .webSearch: $webSearchEnabled
        case .clipboard: $clipboardToolEnabled
        case .selectedText: $selectedTextToolEnabled
        case .screen: $screenToolEnabled
        }
    }

    public func isToolAvailable(_ tool: CloudTool) -> Bool {
        switch tool {
        case .webSearch, .screen: provider != .custom
        case .dateTime, .clipboard, .selectedText: true
        }
    }

    public func isToolMissingPermission(_ tool: CloudTool) -> Bool {
        tool == .screen && screenToolEnabled && !hasScreenRecordingPermission
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

    // Screen Recording has no permission-change notification.
    public func screenRecordingPermissionTask() async {
        guard screenToolEnabled else { return }
        hasScreenRecordingPermission = await permissionsClient.hasScreenRecordingPermission()
        while screenToolEnabled, !hasScreenRecordingPermission {
            do {
                try await clock.sleep(for: .seconds(1))
            } catch {
                return
            }
            hasScreenRecordingPermission = await permissionsClient.hasScreenRecordingPermission()
        }
    }

    public func providerTapped(_ provider: CloudProvider) {
        guard provider != self.provider else { return }
        $provider.withLock { $0 = provider }
        apiKey = savedKeys[provider] ?? ""
        verification = .idle
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
        let revision = verificationRevision
        let connection = connection(apiKey: key)
        func isCurrent() -> Bool {
            verificationRevision == revision && self.connection(apiKey: apiKey.trimmed) == connection
        }
        do {
            try await cloudCleanupClient.verifyKey(connection)
            guard isCurrent() else { return }
            try save(key: key, for: provider)
        } catch {
            guard isCurrent() else { return }
            verification = .failed(error.localizedDescription)
            return
        }

        await loadModels()
        guard isCurrent() else { return }
        if provider == .custom, modelID.rawValue.trimmed.isEmpty, case let .loaded(models) = modelList, let first = models.first {
            modelSelection.withLock { $0 = first.id }
        }
        guard let configuration = configuration(apiKey: key) else {
            verification = .failed("The key works. Choose a model to finish.")
            return
        }
        do {
            try await cloudCleanupClient.checkModel(configuration)
            guard isCurrent() else { return }
            verification = .verified
        } catch {
            guard isCurrent() else { return }
            verification = .failed("The key works, but \(configuration.model) did not answer. \(error.localizedDescription)")
        }
    }

    public func removeKeyButtonTapped() {
        do {
            try save(key: "", for: provider)
            apiKey = ""
            verification = .idle
        } catch {
            verification = .failed(error.localizedDescription)
        }
    }

    public func modelPickerOpened() async {
        guard !modelList.is(\.loaded), !modelList.is(\.loading) else { return }
        await loadModels()
    }

    public func reloadModelsButtonTapped() async {
        await loadModels()
    }

    public func modelSelected(_ id: CloudModel.ID) {
        let id = CloudModel.ID(rawValue: id.rawValue.trimmed)
        guard !id.rawValue.isEmpty else { return }
        modelSelection.withLock { $0 = id }
        verification = .idle
    }

    public func toolToggled(_ tool: CloudTool, isOn: Bool) {
        setting(for: tool).withLock { $0 = isOn }
        if tool == .screen, isOn, !hasScreenRecordingPermission {
            hasScreenRecordingPermission = permissionsClient.requestScreenRecordingPermission()
        }
    }

    private func loadModels() async {
        let provider = provider
        let connection = connection(apiKey: savedKeys[provider] ?? "")
        if provider == .custom, connection.baseURL.isEmpty {
            modelLists[provider] = .failed("Enter a server URL to see its models.")
            return
        }
        if provider != .openRouter, provider.requiresAPIKey, connection.apiKey.isEmpty {
            modelLists[provider] = .failed("Verify your API key to see every model.")
            return
        }
        catalogRevisions[provider, default: 0] += 1
        let revision = catalogRevisions[provider]
        modelLists[provider] = .loading
        let result: ModelList
        do {
            result = .loaded(try await cloudCleanupClient.availableModels(connection))
        } catch {
            result = .failed(error.localizedDescription)
        }
        guard catalogRevisions[provider] == revision, modelLists[provider]?.is(\.loading) == true else { return }
        modelLists[provider] = result
    }

    private func configuration(apiKey: String) -> CloudCleanupConfiguration? {
        let model = CloudModel.ID(rawValue: modelID.rawValue.trimmed)
        guard !model.rawValue.isEmpty, !provider.requiresAPIKey || !apiKey.isEmpty else { return nil }
        if provider == .custom, customBaseURL.trimmed.isEmpty { return nil }
        return CloudCleanupConfiguration(
            connection: connection(apiKey: apiKey),
            model: model,
            systemPrompt: systemPrompt,
            tools: tools
        )
    }

    private func connection(apiKey: String) -> CloudConnection {
        CloudConnection(provider: provider, apiKey: apiKey, baseURL: provider == .custom ? customBaseURL.trimmed : "")
    }

    private func save(key: String, for provider: CloudProvider) throws {
        let previousKey = savedKeys[provider]
        if key.isEmpty {
            try keychainClient.delete(provider.keychainAccount)
            savedKeys[provider] = nil
        } else {
            try keychainClient.setString(key, provider.keychainAccount)
            savedKeys[provider] = key
        }
        if savedKeys[provider] != previousKey {
            modelLists[provider] = nil
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
