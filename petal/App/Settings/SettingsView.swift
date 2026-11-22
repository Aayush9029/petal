import AppFeature
import Shared
import SwiftUI

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: sidebarSelection) {
                Section("Petal") {
                    sidebarRow(.general)
                    sidebarRow(.recording)
                    sidebarRow(.transcription)
                    sidebarRow(.intelligence)
                    sidebarRow(.router)
                }

                Section("Library") {
                    sidebarRow(.history)
                }

                Section("Support") {
                    sidebarRow(.advanced)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(SettingsLayout.sidebarWidth)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            pane
                .id(selectedTab)
                .transition(.opacity)
                .navigationTitle(selectedTab.title)
                .navigationSplitViewColumnWidth(SettingsLayout.detailWidth)
        }
        .navigationSplitViewStyle(.balanced)
        .animation(.easeOut(duration: 0.16), value: selectedTab)
    }

    private var sidebarSelection: Binding<SettingsTab?> {
        Binding(get: { selectedTab }, set: { selectedTab = $0 ?? selectedTab })
    }

    private func sidebarRow(_ tab: SettingsTab) -> some View {
        HStack(spacing: 11) {
            SettingsTabIcon(tab: tab, size: 25)
            Text(tab.title)
                .font(.body.weight(.medium))
        }
        .padding(.vertical, 5)
        .tag(tab)
    }

    @ViewBuilder
    private var pane: some View {
        switch selectedTab {
        case .general:
            GeneralPane(viewModel: viewModel)
        case .transcription:
            TranscriptionPane(viewModel: viewModel)
        case .intelligence:
            IntelligencePane(viewModel: viewModel) { selectedTab = .router }
        case .router:
            RouterPane(viewModel: viewModel) { selectedTab = .intelligence }
        case .recording:
            RecordingPane(viewModel: viewModel)
        case .history:
            HistoryPane(viewModel: viewModel)
        case .advanced:
            AdvancedPane(viewModel: viewModel)
        }
    }
}

#Preview("Settings") {
    SettingsView(viewModel: SettingsViewModel(appModel: AppModel.makePreview()))
        .frame(width: SettingsLayout.windowWidth, height: 680)
}
