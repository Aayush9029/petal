import RouterFeature
import Shared
import SwiftUI

struct RouterPane: View {
    @Bindable var viewModel: SettingsViewModel
    let onOpenIntelligence: () -> Void

    private var router: RouterModel { viewModel.router }

    var body: some View {
        SettingsPaneLayout(tab: .router) {
            if let notice = viewModel.routerNotice {
                RouterNoticeBanner(notice: notice, onOpenIntelligence: onOpenIntelligence)
            }

            SettingsPanelSection(title: "Routes") {
                flowChart
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
            }

            SettingsPanelSection(title: "Instructions") {
                inspectorHeader
                SettingsCardDivider()
                RouteStylePicker(
                    selection: router.selectedStyle,
                    target: router.selectedRoute?.trigger.title ?? "all other apps",
                    onPreset: { router.presetTapped($0) },
                    onCustom: { router.customPromptTapped() },
                    onPasteAsSaid: { router.pasteAsSaidTapped() }
                )
                .padding(14)
                SettingsCardDivider()
                instructions
                    .padding(14)
            }
            .id(router.selection)

            if router.canRunTest {
                SettingsPanelSection(title: "Try It") {
                    CloudTestPanel(sample: Bindable(router).sampleTranscript, testRun: router.testRun) {
                        Task { await router.runTestButtonTapped() }
                    }
                }
            }
        }
        .animation(.smooth(duration: 0.25), value: router.routes)
        .animation(.smooth(duration: 0.2), value: router.selection)
        .animation(.smooth(duration: 0.2), value: router.selectedStyle)
        .task { await router.task() }
        .sheet(isPresented: isShowingPromptEditor) {
            PromptEditorSheet(
                title: "\(router.selectedRoute?.trigger.title ?? "All Other Apps") Instructions",
                text: Binding(get: { router.selectedPrompt }, set: { router.promptChanged($0) }),
                showsVariables: viewModel.cleanupModel != .appleIntelligence,
                isTranscriptTagMissing: router.isTranscriptTagMissing,
                canReset: router.canResetPrompt,
                onAddTranscriptTag: { router.addTranscriptTagButtonTapped() },
                onReset: { router.resetPromptButtonTapped() },
                onDone: { router.promptEditorDoneButtonTapped() }
            )
        }
    }

    private var flowChart: some View {
        RouterFlowChart(
            nodes: nodes,
            selection: router.selection,
            routerCaption: viewModel.cleanupModel == .off ? "Off" : viewModel.cleanupModel.displayName,
            isFlowing: viewModel.routerNotice == nil,
            onSelect: { selection in
                switch selection {
                case .fallback: router.fallbackTapped()
                case let .route(id): router.routeTapped(id)
                }
            }
        ) {
            RouteAddButton(isPresented: router.destination == .addRoute) { router.addRouteButtonTapped() }
                .popover(isPresented: isShowingAddRoute, arrowEdge: .bottom) {
                    RouteAddPopover(
                        query: router.addRouteQuery,
                        apps: router.addRouteApps,
                        website: router.addRouteWebsite,
                        onQueryChange: { router.addRouteQuery = $0 },
                        onApp: { router.runningAppTapped($0) },
                        onWebsite: { router.websiteTapped() },
                        onSubmit: { router.addRouteSubmitted() },
                        onChooseApplication: { router.chooseApplicationButtonTapped() }
                    )
                }
        }
    }

    private var nodes: [RouterFlowNode] {
        router.routes.map { route in
            RouterFlowNode(id: .route(route.id), trigger: route.trigger, style: router.style(of: .route(route.id)))
        } + [RouterFlowNode(id: .fallback, trigger: nil, style: router.style(of: .fallback))]
    }

    private var inspectorHeader: some View {
        HStack(spacing: 12) {
            RouteIcon(trigger: router.selectedRoute?.trigger, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(router.selectedRoute?.trigger.title ?? "All Other Apps")
                    .font(.body.weight(.semibold))
                Text(scopeDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let route = router.selectedRoute {
                Button("Remove", role: .destructive) {
                    router.removeRouteButtonTapped(route.id)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .font(.callout)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var instructions: some View {
        if router.selectedStyle == .pasteAsSaid {
            Label(pasteAsSaidDescription, systemImage: "quote.bubble")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                PromptPreview(text: router.selectedPrompt) { router.promptEditorTapped() }

                if router.isTranscriptTagMissing {
                    TranscriptTagWarning { router.addTranscriptTagButtonTapped() }
                }

                HStack(alignment: .firstTextBaseline) {
                    Text(instructionsFootnote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if router.canResetPrompt {
                        SettingsActionButton(title: "Reset") { router.resetPromptButtonTapped() }
                    }
                }
            }
        }
    }

    private var scopeDescription: String {
        switch router.selectedRoute?.trigger {
        case let .app(app)?: app.bundleID
        case .website?: "Any browser tab on this website or its subdomains"
        case nil: "Every app and website without its own route"
        }
    }

    private var pasteAsSaidDescription: String {
        switch router.selectedRoute?.trigger {
        case let .app(app)?: "Petal skips cleanup in \(app.name) and pastes your words as you said them."
        case let .website(domain)?: "Petal skips cleanup on \(domain) and pastes your words as you said them."
        case nil: "Petal cleans up only in apps with their own route. Everywhere else, it pastes your words as you said them."
        }
    }

    private var instructionsFootnote: String {
        switch viewModel.cleanupModel {
        case .appleIntelligence: "Apple Intelligence follows these instructions. Click the prompt to edit it."
        case .petalW1: "Apple Intelligence and cloud models follow these instructions. Petal W1 uses its own style."
        case .off, .cloud: "Click the prompt to edit it and insert variables, such as your name or the window title."
        }
    }

    private var isShowingPromptEditor: Binding<Bool> {
        Binding(
            get: { router.destination == .promptEditor },
            set: { if !$0 { router.promptEditorDoneButtonTapped() } }
        )
    }

    private var isShowingAddRoute: Binding<Bool> {
        Binding(
            get: { router.destination == .addRoute },
            set: { if !$0 { router.addRouteDismissed() } }
        )
    }
}

#Preview {
    RouterPane(viewModel: SettingsViewModel(appModel: AppModel.makePreview())) {}
        .frame(width: 515, height: 900)
}
