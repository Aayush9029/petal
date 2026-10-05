import ApplicationsClient
import CloudCleanupClient
import CloudCleanupFeature
import DebugSnapshots
import Foundation
import FoundationModelClient
import Observation
import Shared

/// Decides which instructions cleanup uses for each app and website, and edits them.
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

    @ObservationIgnored @Shared(.cleanupRoutes) public var routes: IdentifiedArrayOf<CleanupRoute> = []
    @ObservationIgnored @Shared(.cleanupFallbackAction) public var fallbackAction: CleanupRoute.Action = .cleanUp
    @ObservationIgnored @Shared(.cleanupModel) public var cleanupModel: CleanupModel = .off
    @ObservationIgnored @Shared(.cloudSystemPrompt) public var cloudSystemPrompt: String = CloudPromptPreset.cleanUp.prompt
    @ObservationIgnored @Shared(.smartPrompt) public var smartPrompt: String = TranscriptionMode.defaultSmartPrompt

    public var selection: Selection = .fallback
    public var destination: Destination?
    /// Filters open apps and accepts a website address in the add popover.
    public var addRouteQuery: String = ""
    public var sampleTranscript: String = CloudPromptPreset.cleanUp.sampleTranscript
    public var testRun: TestRun = .idle
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

    /// Apple Intelligence keeps its own tuned default, so the fallback edits a different prompt for it.
    public var fallbackUsesSmartPrompt: Bool {
        cleanupModel == .appleIntelligence
    }

    /// Petal W1 has a built-in style, so only Paste As Said routes change what it does.
    public var cleanupUsesPrompts: Bool {
        cleanupModel == .appleIntelligence || cleanupModel == .cloud
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

    /// Only cloud models read the tag. Petal adds the sentence anyway, so this is a hint, not an error.
    public var isTranscriptTagMissing: Bool {
        cleanupModel == .cloud && !CloudPromptTranscript.isMentioned(in: selectedPrompt)
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

    /// Only text that looks like an address becomes a website, so typing an app name does not offer "slack" as a site.
    public var addRouteWebsite: String? {
        let query = addRouteQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.contains(".") || query.lowercased().hasPrefix("localhost") else { return nil }
        return CleanupRoute.domain(from: query)
    }

    /// Polls because the add menu has no open event, and launches and quits should show without reopening Settings.
    public func task() async {
        while !Task.isCancelled {
            runningApps = applicationsClient.runningApplications()
            do {
                try await clock.sleep(for: .seconds(3))
            } catch {
                return
            }
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

    /// Return adds the website when the text is an address, or the only app that matches.
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
            let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            prompt = trimmed.isEmpty ? CloudPromptTranscript.sentence : "\(trimmed)\n\n\(CloudPromptTranscript.sentence)"
        }
    }

    public func runTestButtonTapped() async {
        let transcript = sampleTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty, canRunTest else { return }
        let prompt = selectedPrompt
        switch cleanupModel {
        case .cloud:
            guard var configuration = cloud.configuration else {
                testRun = .failed(cloud.provider.requiresAPIKey ? "Verify an API key first." : "Enter a server URL and a model first.")
                return
            }
            configuration.systemPrompt = prompt
            testRun = .running
            do {
                testRun = .finished(try await cloudCleanupClient.clean(transcript, configuration))
            } catch {
                testRun = .failed(error.localizedDescription)
            }
        case .appleIntelligence:
            testRun = .running
            do {
                var text = ""
                let elapsed = try await clock.measure {
                    text = try await foundationModelClient.refine(transcript, prompt)
                }
                testRun = .finished(CloudCleanupResult(text: text, elapsed: elapsed))
            } catch {
                testRun = .failed(error.localizedDescription)
            }
        case .off, .petalW1:
            return
        }
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
