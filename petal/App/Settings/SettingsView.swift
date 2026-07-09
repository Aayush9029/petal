import Assets
import AudioClient
import KeyboardShortcuts
import ModelDownloadFeature
import Shared
import SwiftUI
import UI

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
                }

                Section("Library") {
                    sidebarRow(.history)
                }

                Section("Support") {
                    sidebarRow(.advanced)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Settings")
            .navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 250)
        } detail: {
            pane
                .id(selectedTab)
                .transition(.opacity.combined(with: .scale(scale: 0.995)))
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
        case .recording:
            RecordingPane(viewModel: viewModel)
        case .history:
            HistoryPane(viewModel: viewModel)
        case .advanced:
            AdvancedPane(viewModel: viewModel)
        }
    }
}

struct GeneralPane: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        SettingsPaneLayout(tab: .general) {
            SettingsSectionGroup(
                title: "Recording Shortcut",
                subtitle: "Choose how Petal starts and stops listening."
            ) {
                SettingsControlRow(
                    title: "Shortcut",
                    description: viewModel.shortcutDescription,
                    symbol: "keyboard"
                ) {
                    UnifiedShortcutRecorder(shortcut: viewModel.unifiedShortcutBinding)
                }

                SettingsCardDivider()

                SettingsControlRow(
                    title: "Hold Duration",
                    description: "How long a press becomes push-to-talk.",
                    symbol: "timer"
                ) {
                    Picker("Hold Duration", selection: Binding(viewModel.$pushToTalkThreshold)) {
                        ForEach(PushToTalkThreshold.allCases) { threshold in
                            Text(threshold.displayName).tag(threshold)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                }
            }

            SettingsSectionGroup(
                title: "Appearance",
                subtitle: "Choose how the floating recording bar looks on your desktop."
            ) {
                CapsuleAppearancePicker(selection: viewModel.floatingCapsuleBackgroundStyle) { style in
                    withAnimation(.snappy(duration: 0.24)) {
                        viewModel.floatingCapsuleBackgroundStyle = style
                    }
                }
            }

            if !viewModel.microphoneAuthorized || !viewModel.accessibilityAuthorized {
                SettingsSectionGroup(
                    title: "Permissions Needed",
                    subtitle: "Only missing permissions are shown."
                ) {
                    if !viewModel.microphoneAuthorized {
                        permissionRow(
                            title: "Microphone",
                            description: "Required to hear and transcribe your voice.",
                            symbol: "mic.fill"
                        ) {
                            await viewModel.grantMicrophonePermissionButtonTapped()
                        }
                    }

                    if !viewModel.microphoneAuthorized && !viewModel.accessibilityAuthorized {
                        SettingsCardDivider()
                    }

                    if !viewModel.accessibilityAuthorized {
                        permissionRow(
                            title: "Accessibility",
                            description: "Allows Petal to paste into the app you are using.",
                            symbol: "accessibility"
                        ) {
                            await viewModel.grantAccessibilityPermissionButtonTapped()
                        }
                    }

                    if let message = viewModel.permissionMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(.top, 8)
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task {
            await viewModel.refreshPermissions()
        }
        .animation(.smooth(duration: 0.3), value: viewModel.microphoneAuthorized)
        .animation(.smooth(duration: 0.3), value: viewModel.accessibilityAuthorized)
    }

    private func permissionRow(
        title: String,
        description: String,
        symbol: String,
        action: @escaping () async -> Void
    ) -> some View {
        SettingsControlRow(title: title, description: description, symbol: symbol) {
            Button("Enable") {
                Task { await action() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }
}

struct RecordingPane: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        SettingsPaneLayout(tab: .recording) {
            SettingsSectionGroup(
                title: "Input",
                subtitle: "Petal falls back to the system default if this device disappears."
            ) {
                SettingsControlRow(title: "Microphone", symbol: "mic") {
                    Picker("Microphone", selection: Binding(
                        get: { viewModel.selectedAudioInputID },
                        set: { viewModel.selectedAudioInputID = $0 }
                    )) {
                        ForEach(viewModel.audioInputDevices) { device in
                            Text(device.name).tag(device.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 250)
                }
            }

            SettingsSectionGroup(title: "Audio Processing") {
                SettingsToggleRow(
                    title: "Trim Silence",
                    description: "Remove quiet segments from the start and end.",
                    symbol: "waveform.badge.minus",
                    isOn: Binding(viewModel.$trimSilenceEnabled)
                )
                SettingsCardDivider()
                SettingsToggleRow(
                    title: "Auto Speed-up",
                    description: "Speed up low-energy audio to reduce transcription time.",
                    symbol: "gauge.with.dots.needle.50percent",
                    isOn: Binding(viewModel.$autoSpeedEnabled)
                )
            }

            SettingsSectionGroup(title: "Behavior") {
                SettingsToggleRow(
                    title: "Restore Clipboard After Paste",
                    description: "Put the previous clipboard contents back after auto-pasting.",
                    symbol: "clipboard",
                    isOn: Binding(viewModel.$restoreClipboardAfterPaste)
                )
                SettingsCardDivider()
                SettingsToggleRow(
                    title: "Lower System Audio",
                    description: "Reduce output volume while recording and restore it afterward.",
                    symbol: "speaker.wave.1",
                    isOn: Binding(viewModel.$duckSystemAudioDuringRecording)
                )
            }
        }
        .task {
            await viewModel.refreshAudioInputDevices()
        }
    }
}

struct TranscriptionPane: View {
    @Bindable var viewModel: SettingsViewModel
    @State private var destination: TranscriptionDestination?

    var body: some View {
        SettingsPaneLayout(tab: .transcription) {
            SettingsSectionGroup(
                title: "Transcription Model",
                subtitle: "Downloaded models stay on this Mac."
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    if let pinnedDownloadOption = viewModel.pinnedDownloadOption {
                        modelCard(for: pinnedDownloadOption)
                    }

                    ForEach(viewModel.modelProviderGroups) { group in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(group.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.leading, 4)

                            ForEach(group.options) { option in
                                modelCard(for: option)
                            }
                        }
                    }
                }
            }

            SettingsSectionGroup(title: "Intelligence") {
                if viewModel.appleIntelligenceAvailable {
                    SettingsToggleRow(
                        title: "Enhance with Apple Intelligence",
                        description: "Polish grammar, punctuation, and formatting on-device.",
                        symbol: "apple.intelligence",
                        isOn: Binding(viewModel.$appleIntelligenceEnabled)
                    )
                } else {
                    SettingsControlRow(
                        title: "Apple Intelligence",
                        description: "Requires macOS 26 with Apple Intelligence enabled.",
                        symbol: "apple.intelligence"
                    ) {
                        Text("Unavailable")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if viewModel.smartModeAvailable {
                SettingsSectionGroup(title: "Writing Style") {
                    SettingsControlRow(
                        title: "Mode",
                        description: viewModel.transcriptionMode.description,
                        symbol: "text.badge.checkmark"
                    ) {
                        Picker("Transcription Mode", selection: Binding(viewModel.$transcriptionMode)) {
                            ForEach(TranscriptionMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 190)
                    }

                    if viewModel.transcriptionMode == .smart {
                        SettingsCardDivider()
                        TextField("Smart prompt", text: Binding(viewModel.$smartPrompt), axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(3 ... 6)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.smooth(duration: 0.25), value: viewModel.transcriptionMode)
        .alert(
            "Delete Download",
            isPresented: isShowingDeleteConfirmation,
            presenting: deleteConfirmationOption
        ) { option in
            Button("Delete", role: .destructive) {
                Task {
                    await viewModel.deleteDownloadedModel(option)
                    destination = nil
                }
            }
            Button("Cancel", role: .cancel) { destination = nil }
        } message: { option in
            Text("Remove \(option.displayName) from this Mac? You can download it again later.")
        }
    }

    private func modelCard(for option: ModelOption) -> some View {
        ModelSelectorCard(
            option: option,
            isSelected: viewModel.selectedModelID == option.rawValue,
            isWarming: viewModel.selectedModelID == option.rawValue && viewModel.isWarmingModel,
            downloadState: downloadState(for: option),
            isEnabled: !viewModel.downloadModel.isDeletingModel(option),
            onDeleteDownloadedModel: { destination = .deleteModel(option) },
            onPauseDownload: { viewModel.pauseButtonTapped() },
            onResumeDownload: { Task { await viewModel.resumeButtonTapped() } },
            onCancelDownload: { viewModel.cancelButtonTapped() }
        ) {
            if let option = viewModel.modelOptionTapped(option) {
                Task { await viewModel.downloadModelConfirmed(option) }
            }
        }
    }

    private func downloadState(for option: ModelOption) -> ModelSelectorCard.DownloadState {
        guard option.requiresDownload else { return .ready }
        guard !viewModel.downloadModel.isDeletingModel(option) else { return .deleting }

        let state = viewModel.downloadModel.state
        if viewModel.downloadModel.downloadingModelOption == option {
            switch state {
            case .downloaded: return .ready
            case .notDownloaded: break
            case .preparing: return .preparing
            case let .downloading(progress): return .downloading(progress)
            case let .paused(progress): return .paused(progress)
            case let .failed(message): return .failed(message)
            }
        }

        return viewModel.downloadModel.isModelDownloaded(option) ? .ready : .needsDownload
    }

    private var deleteConfirmationOption: ModelOption? {
        guard case let .deleteModel(option) = destination else { return nil }
        return option
    }

    private var isShowingDeleteConfirmation: Binding<Bool> {
        Binding(
            get: { deleteConfirmationOption != nil },
            set: { if !$0 { destination = nil } }
        )
    }
}

private enum TranscriptionDestination {
    case deleteModel(ModelOption)
}

struct HistoryPane: View {
    @Bindable var viewModel: SettingsViewModel
    @State private var historyAlert: HistoryAlert?

    var body: some View {
        SettingsPaneLayout(tab: .history) {
            if !viewModel.recentHistoryEntries.isEmpty {
                SettingsSectionGroup(title: "Recent") {
                    ForEach(Array(viewModel.recentHistoryEntries.enumerated()), id: \.element.id) { index, entry in
                        let transcript = viewModel.transcriptText(for: entry)
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(transcript)
                                    .lineLimit(2)
                                Text(entry.timestamp, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                viewModel.copyHistoryEntry(entry)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                            .help("Copy transcript")
                        }

                        if index < viewModel.recentHistoryEntries.count - 1 {
                            SettingsCardDivider()
                        }
                    }
                }
            }

            SettingsSectionGroup(title: "Storage") {
                SettingsControlRow(title: "Keep", symbol: "clock.arrow.circlepath") {
                    Picker("Keep", selection: Binding(
                        get: { viewModel.historyRetentionMode },
                        set: { viewModel.historyRetentionModeChanged($0) }
                    )) {
                        ForEach(HistoryRetentionMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                }

                SettingsCardDivider()

                SettingsToggleRow(
                    title: "Extra Compression",
                    description: "Use lower-bitrate AAC files for saved audio.",
                    symbol: "archivebox",
                    isOn: Binding(viewModel.$compressHistoryAudio)
                )

                SettingsCardDivider()

                SettingsControlRow(
                    title: "Location",
                    description: viewModel.historyDirectoryPath,
                    symbol: "folder"
                ) {
                    Button("Show in Finder") { viewModel.openHistoryInFinder() }
                        .controlSize(.small)
                }
            }

            SettingsSectionGroup(title: "Clear Data") {
                HStack(spacing: 10) {
                    Button("Delete Media", role: .destructive) { historyAlert = .deleteMedia }
                    Button("Delete All History", role: .destructive) { historyAlert = .deleteAll }
                }
                .buttonStyle(.bordered)
            }
        }
        .alert(historyAlert?.title ?? "", isPresented: isShowingHistoryAlert) {
            if let historyAlert {
                Button(historyAlert.confirmTitle, role: .destructive) {
                    performHistoryAction(for: historyAlert)
                    self.historyAlert = nil
                }
            }
            Button("Cancel", role: .cancel) { historyAlert = nil }
        } message: {
            if let historyAlert { Text(historyAlert.message) }
        }
    }

    private var isShowingHistoryAlert: Binding<Bool> {
        Binding(get: { historyAlert != nil }, set: { if !$0 { historyAlert = nil } })
    }

    private func performHistoryAction(for alert: HistoryAlert) {
        switch alert {
        case .deleteAll: viewModel.deleteAllHistory()
        case .deleteMedia: viewModel.deleteMediaOnly()
        }
    }
}

private enum HistoryAlert {
    case deleteAll
    case deleteMedia

    var title: String {
        switch self {
        case .deleteAll: "Delete All History & Media"
        case .deleteMedia: "Delete Media Only"
        }
    }

    var confirmTitle: String {
        switch self {
        case .deleteAll: "Delete All"
        case .deleteMedia: "Delete Media"
        }
    }

    var message: String {
        switch self {
        case .deleteAll: "This permanently deletes all transcription history, audio, and transcript files."
        case .deleteMedia: "This deletes saved audio files but keeps transcription history."
        }
    }
}

struct AdvancedPane: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        SettingsPaneLayout(tab: .advanced) {
            SettingsSectionGroup(
                title: "Diagnostics",
                subtitle: "Logging stays off unless you explicitly enable it."
            ) {
                SettingsToggleRow(
                    title: "Enable Logs",
                    description: "Write diagnostic information to a local log file.",
                    symbol: "doc.text.magnifyingglass",
                    isOn: Binding(viewModel.$logsEnabled)
                )
                SettingsCardDivider()
                SettingsControlRow(
                    title: "Export Logs",
                    description: "Save a copy to share while troubleshooting.",
                    symbol: "square.and.arrow.up"
                ) {
                    Button("Export…") { viewModel.exportLogs() }
                        .disabled(!viewModel.canExportLogs)
                }
            }
        }
    }
}

#Preview("Settings") {
    SettingsView(viewModel: SettingsViewModel(appModel: AppModel.makePreview()))
        .frame(width: 920, height: 720)
}
