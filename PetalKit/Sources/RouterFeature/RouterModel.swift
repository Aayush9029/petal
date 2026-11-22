import ApplicationsClient
import CloudCleanupClient
import CloudCleanupFeature
import DebugSnapshots
import Foundation
import FoundationModelClient
import Observation
import Shared

@DebugSnapshot
@MainActor
@Observable
public final class RouterModel {
    @CasePathable
    @dynamicMemberLookup
    public enum Selection: Hashable, Sendable {
        case fallback
        case route(CleanupRoute.ID)
    }

    @CasePathable
    public enum Destination: Hashable, Identifiable, Sendable {
        case promptEditor
        case addRoute

        public var id: Self { self }
    }

    @CasePathable
    public enum Style: Hashable, Sendable {
        case preset(CloudPromptPreset)
        case custom
        case pasteAsSaid
    }

    @CasePathable
    public enum TestRun: Equatable, Sendable {
        case idle
        case running
        case finished(CloudCleanupResult)
        case failed(String)
    }

    @ObservationIgnored @Shared(.cleanupRoutes) public var routes: IdentifiedArrayOf<CleanupRoute>
    @ObservationIgnored @Shared(.cleanupFallbackAction) public var fallbackAction: CleanupRoute.Action
    @ObservationIgnored @Shared(.cleanupModel) public var cleanupModel: CleanupModel
    @ObservationIgnored @Shared(.cloudSystemPrompt) public var cloudSystemPrompt: String
    @ObservationIgnored @Shared(.smartPrompt) public var smartPrompt: String

    public var selection: Selection = .fallback
    public var destination: Destination?
    public var addRouteQuery: String = ""
    public var sampleTranscript: String = CloudPromptPreset.cleanUp.sampleTranscript
    public var testRun: TestRun = .idle {
        didSet { testRunRevision += 1 }
    }
    @ObservationIgnored @DebugSnapshotIgnored private var testRunRevision = 0
    public private(set) var runningApps: [MacApp] = []
    /// The preset each prompt started from, so Reset returns there after the user edits it.
    public private(set) var basePresets: [Selection: CloudPromptPreset] = [:]

    @ObservationIgnored @DebugSnapshotIgnored let cloud: CloudCleanupModel
    @ObservationIgnored @Dependency(\.applicationsClient) private var applicationsClient
    @ObservationIgnored @Dependency(\.cloudCleanupClient) private var cloudCleanupClient
    @ObservationIgnored @Dependency(\.foundationModelClient) private var foundationModelClient
    @ObservationIgnored @Dependency(\.continuousClock) private var clock
    @ObservationIgnored @Dependency(\.uuid) private var uuid

    public init(cloud: CloudCleanupModel) {
        self.cloud = cloud
    }

    public var fallbackUsesSmartPrompt: Bool {
        cleanupModel == .appleIntelligence
    }

    /// Petal W1 has a built-in style, so only Paste As Said routes change what it does.
    public var cleanupUsesPrompts: Bool {
        effectiveCleanupModel == .appleIntelligence || effectiveCleanupModel == .cloud
    }

    public var effectiveCleanupModel: CleanupModel {
        selectedRoute?.cleanupModel ?? cleanupModel
    }

    public var selectedRoute: CleanupRoute? {
        selection.route.flatMap { routes[id: $0] }
    }

    public var selectedAction: CleanupRoute.Action {
        action(of: selection)
    }

    public var selectedPrompt: String {
        prompt(of: selection)
    }

    public var selectedPreset: CloudPromptPreset? {
        preset(of: selection)
    }

    public var selectedStyle: Style {
        style(of: selection)
    }

    public var resetPrompt: String {
        if let preset = selectedPreset ?? basePresets[selection] {
            return prompt(for: preset, in: selection)
        }
        let preset = selectedRoute.map { CloudPromptPreset.suggested(for: $0.trigger) } ?? .cleanUp
        return prompt(for: preset, in: selection)
    }

    public func style(of selection: Selection) -> Style {
        if action(of: selection) == .pasteAsSaid { return .pasteAsSaid }
        return preset(of: selection).map(Style.preset) ?? .custom
    }

    public func action(of selection: Selection) -> CleanupRoute.Action {
        switch selection {
        case .fallback: fallbackAction
        case let .route(id): routes[id: id]?.action ?? fallbackAction
        }
    }

    public func prompt(of selection: Selection) -> String {
        switch selection {
        case .fallback: fallbackUsesSmartPrompt ? smartPrompt : cloudSystemPrompt
        case let .route(id): routes[id: id]?.prompt ?? cloudSystemPrompt
        }
    }

    private func preset(of selection: Selection) -> CloudPromptPreset? {
        let prompt = prompt(of: selection)
        if prompt == self.prompt(for: .cleanUp, in: selection) { return .cleanUp }
        return CloudPromptPreset.matching(prompt)
    }

    /// Apple Intelligence's Clean Up is its own tuned default, because the small on-device model follows it better.
    private func prompt(for preset: CloudPromptPreset, in selection: Selection) -> String {
        if selection == .fallback, fallbackUsesSmartPrompt, preset == .cleanUp {
            return TranscriptionMode.defaultSmartPrompt
        }
        return preset.prompt
    }

    public var canResetPrompt: Bool {
        selectedPrompt != resetPrompt
    }

    public var isTranscriptTagMissing: Bool {
        effectiveCleanupModel == .cloud && !CloudPromptTranscript.isMentioned(in: selectedPrompt)
    }

    public var routeCleanupModels: Set<CleanupModel> {
        Set(routes.filter { $0.action == .cleanUp }.compactMap(\.cleanupModel))
    }

    public var canPickCleanupModel: Bool {
        selectedRoute != nil && selectedAction == .cleanUp
    }

    public var selectedCleanupModel: CleanupModel? {
        get { selectedRoute?.cleanupModel }
        set {
            guard canPickCleanupModel, let id = selection.route else { return }
            $routes.withLock { $0[id: id]?.cleanupModel = newValue }
            testRun = .idle
        }
    }

    public var canRunTest: Bool {
        cleanupUsesPrompts && selectedAction == .cleanUp
    }

    public var addableRunningApps: [MacApp] {
        runningApps.filter { routes.route(with: .app($0)) == nil }
    }

    public var addRouteApps: [MacApp] {
        let query = addRouteQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return addableRunningApps }
        return addableRunningApps.filter { $0.name.localizedStandardContains(query) }
    }

    public var addRouteWebsite: String? {
        let query = addRouteQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.contains(".") || query.lowercased().hasPrefix("localhost") else { return nil }
        return CleanupRoute.domain(from: query)
    }

    public func task() async {
        for await apps in applicationsClient.runningApplications() {
            runningApps = apps
        }
    }

    public func fallbackTapped() {
        select(.fallback)
    }

    public func routeTapped(_ id: CleanupRoute.ID) {
        select(.route(id))
    }

    public func addRouteButtonTapped() {
        addRouteQuery = ""
        destination = .addRoute
    }

    public func addRouteDismissed() {
        guard destination == .addRoute else { return }
        destination = nil
    }

    public func runningAppTapped(_ app: MacApp) {
        addRouteDismissed()
        addRoute(.app(app))
    }

    public func websiteTapped() {
        guard let domain = addRouteWebsite else { return }
        addRouteDismissed()
        addRoute(.website(domain))
    }

    public func addRouteSubmitted() {
        if addRouteWebsite != nil {
            websiteTapped()
        } else if addRouteApps.count == 1, let app = addRouteApps.first {
            runningAppTapped(app)
        }
    }

    public func chooseApplicationButtonTapped() {
        addRouteDismissed()
        guard let app = applicationsClient.chooseApplication() else { return }
        addRoute(.app(app))
    }

    public func removeRouteButtonTapped(_ id: CleanupRoute.ID) {
        $routes.withLock { _ = $0.remove(id: id) }
        basePresets[.route(id)] = nil
        if selection == .route(id) {
            select(.fallback)
        }
    }

    public func presetTapped(_ preset: CloudPromptPreset) {
        let presetPrompt = prompt(for: preset, in: selection)
        updateSelection { action, prompt in
            action = .cleanUp
            prompt = presetPrompt
        }
        basePresets[selection] = preset
        sampleTranscript = preset.sampleTranscript
        testRun = .idle
    }

    public func pasteAsSaidTapped() {
        updateSelection { action, _ in action = .pasteAsSaid }
        testRun = .idle
    }

    public func customPromptTapped() {
        updateSelection { action, _ in action = .cleanUp }
        destination = .promptEditor
    }

    public func promptEditorTapped() {
        destination = .promptEditor
    }

    public func promptEditorDoneButtonTapped() {
        destination = nil
    }

    public func promptChanged(_ prompt: String) {
        updateSelection { _, current in current = prompt }
    }

    public func resetPromptButtonTapped() {
        let prompt = resetPrompt
        updateSelection { _, current in current = prompt }
    }

    public func addTranscriptTagButtonTapped() {
        guard isTranscriptTagMissing else { return }
        updateSelection { _, prompt in
            prompt = CloudPromptTranscript.instructions(for: prompt).joined(separator: "\n\n")
        }
    }

    public func runTestButtonTapped() async {
        let transcript = sampleTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty, canRunTest else { return }
        let prompt = selectedPrompt
        let engine = effectiveCleanupModel
        testRun = .running
        let revision = testRunRevision
        let result: TestRun
        do {
            switch engine {
            case .cloud:
                guard var configuration = cloud.configuration else {
                    testRun = .failed(cloud.provider.requiresAPIKey ? "Verify an API key first." : "Enter a server URL and a model first.")
                    return
                }
                configuration.systemPrompt = prompt
                result = .finished(try await cloudCleanupClient.clean(transcript, configuration))
            case .appleIntelligence:
                var text = ""
                let elapsed = try await clock.measure {
                    text = try await foundationModelClient.refine(transcript, prompt)
                }
                result = .finished(CloudCleanupResult(text: text, elapsed: elapsed))
            case .off, .petalW1:
                return
            }
        } catch {
            result = .failed(error.localizedDescription)
        }
        guard testRunRevision == revision else { return }
        testRun = result
    }

    private func select(_ selection: Selection) {
        guard selection != self.selection else { return }
        self.selection = selection
        sampleTranscript = (selectedPreset ?? basePresets[selection] ?? .cleanUp).sampleTranscript
        testRun = .idle
    }

    private func addRoute(_ trigger: CleanupRoute.Trigger) {
        if let existing = routes.route(with: trigger) {
            select(.route(existing.id))
            return
        }
        let preset = CloudPromptPreset.suggested(for: trigger)
        let route = CleanupRoute(id: CleanupRoute.ID(uuid()), trigger: trigger, prompt: preset.prompt)
        $routes.withLock { _ = $0.append(route) }
        basePresets[.route(route.id)] = preset
        select(.route(route.id))
    }

    private func updateSelection(_ update: (inout CleanupRoute.Action, inout String) -> Void) {
        switch selection {
        case let .route(id):
            $routes.withLock { routes in
                guard var route = routes[id: id] else { return }
                update(&route.action, &route.prompt)
                routes[id: id] = route
            }
        case .fallback:
            var action = fallbackAction
            var prompt = prompt(of: .fallback)
            update(&action, &prompt)
            $fallbackAction.withLock { $0 = action }
            if fallbackUsesSmartPrompt {
                $smartPrompt.withLock { $0 = prompt }
            } else {
                $cloudSystemPrompt.withLock { $0 = prompt }
            }
        }
    }
}
