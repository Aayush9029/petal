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
            .navigationSplitViewColumnWidth(min: 190, ideal: 205, max: 220)
        } detail: {
            pane
                .id(selectedTab)
                .transition(.opacity)
                .navigationTitle(selectedTab.title)
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
            SettingsPanel {
                SettingsControlRow(
                    title: "Recording Shortcut",
                    description: viewModel.shortcutDescription
                ) {
                    UnifiedShortcutRecorder(shortcut: viewModel.unifiedShortcutBinding)
                }

                SettingsCardDivider()

                SettingsControlRow(
                    title: "Hold Duration"
                ) {
                    SettingsSegmentedPicker(
                        values: PushToTalkThreshold.allCases,
                        selection: viewModel.pushToTalkThreshold,
                        title: \.displayName
                    ) { threshold in
                        viewModel.$pushToTalkThreshold.withLock { $0 = threshold }
                    }
                    .frame(width: 205)
                }
            }

            SettingsPanel {
                CapsuleAppearancePicker(selection: viewModel.floatingCapsuleBackgroundStyle) { style in
                    withAnimation(.snappy(duration: 0.24)) {
                        viewModel.$floatingCapsuleBackgroundStyle.withLock { $0 = style }
                    }
                }
                .padding(14)
            }

            if !viewModel.microphoneAuthorized || !viewModel.accessibilityAuthorized {
                SettingsPanel {
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
                            .padding(14)
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
            SettingsActionButton(title: "Enable") {
                Task { await action() }
            }
        }
    }
}

struct RecordingPane: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        SettingsPaneLayout(tab: .recording) {
            SettingsPanel {
                SettingsControlRow(title: "Microphone", symbol: "mic") {
                    SettingsMenuPicker(
                        values: viewModel.audioInputDevices.map(\.id),
                        selection: viewModel.selectedAudioInputID,
                        title: microphoneTitle
                    ) { id in
                        viewModel.selectedAudioInputID = id
                    }
                    .frame(maxWidth: 220)
                }
            }

            SettingsPanel {
                VStack(spacing: 0) {
                    RecordingOptionTile(
                        title: "Trim Silence",
                        description: "Remove quiet gaps from recordings.",
                        symbol: "scissors",
                        isOn: viewModel.trimSilenceEnabled
                    ) { viewModel.$trimSilenceEnabled.withLock { $0.toggle() } }

                    SettingsCardDivider()

                    RecordingOptionTile(
                        title: "Auto Speed-up",
                        description: "Accelerate long recordings automatically.",
                        symbol: "hare.fill",
                        isOn: viewModel.autoSpeedEnabled
                    ) { viewModel.$autoSpeedEnabled.withLock { $0.toggle() } }

                    SettingsCardDivider()

                    RecordingOptionTile(
                        title: "Restore Clipboard",
                        description: "Put previous clipboard content back.",
                        symbol: "clipboard",
                        isOn: viewModel.restoreClipboardAfterPaste
                    ) { viewModel.$restoreClipboardAfterPaste.withLock { $0.toggle() } }

                    SettingsCardDivider()

                    RecordingOptionTile(
                        title: "Lower System Audio",
                        description: "Quiet other audio while recording.",
                        symbol: "speaker.wave.1",
                        isOn: viewModel.duckSystemAudioDuringRecording
                    ) { viewModel.$duckSystemAudioDuringRecording.withLock { $0.toggle() } }
                }
            }
        }
        .task {
            await viewModel.refreshAudioInputDevices()
        }
    }

    private func microphoneTitle(_ id: String) -> String {
        guard id != AudioInputDevice.systemDefaultID else { return "Default" }
        let name = viewModel.audioInputDevices.first(where: { $0.id == id })?.name ?? "Default"
        return name.replacingOccurrences(of: " (Current Default)", with: "")
    }
}

struct TranscriptionPane: View {
    @Bindable var viewModel: SettingsViewModel
    @State private var destination: TranscriptionDestination?

    var body: some View {
        SettingsPaneLayout(tab: .transcription) {
            SettingsPanelSection(title: "Speech Model") {
                ForEach(Array(visibleModelOptions.enumerated()), id: \.element) { index, option in
                    modelCard(for: option)
                    if index < visibleModelOptions.count - 1 {
                        SettingsCardDivider()
                    }
                }
            }

            if viewModel.appleIntelligenceAvailable || viewModel.smartModeAvailable {
                SettingsPanelSection(title: "Enhancement") {
                    if viewModel.appleIntelligenceAvailable {
                        SettingsControlRow(
                            title: "Enhance with Apple Intelligence",
                            description: "Refine transcripts on-device after speech recognition."
                        ) {
                            HStack(spacing: 10) {
                                IntelligenceProcessingWaveform(
                                    bars: 11,
                                    rows: 5,
                                    isAnimated: viewModel.appleIntelligenceEnabled
                                )
                                SettingsSwitch(
                                    isOn: viewModel.appleIntelligenceEnabled
                                ) { value in
                                    viewModel.$appleIntelligenceEnabled.withLock { $0 = value }
                                }
                            }
                        }
                    }

                    if viewModel.appleIntelligenceAvailable && viewModel.smartModeAvailable {
                        SettingsCardDivider()
                    }

                    if viewModel.smartModeAvailable {
                        SettingsControlRow(
                            title: "Writing Style"
                        ) {
                            SettingsSegmentedPicker(
                                values: TranscriptionMode.allCases,
                                selection: viewModel.transcriptionMode,
                                title: \.displayName
                            ) { mode in
                                viewModel.$transcriptionMode.withLock { $0 = mode }
                            }
                            .frame(width: 205)
                        }

                        if viewModel.transcriptionMode == .smart {
                            SettingsCardDivider()
                            TextField("Smart prompt", text: Binding(viewModel.$smartPrompt), axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(3 ... 6)
                                .padding(14)
                        }
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

    private var visibleModelOptions: [ModelOption] {
        var seen = Set<ModelOption>()
        let options = viewModel.modelProviderGroups.flatMap(\.options)
        return options.filter { seen.insert($0).inserted }
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
            set: {
                if !$0 {
                    destination = nil
                }
            }
        )
    }
}

private enum TranscriptionDestination {
    case deleteModel(ModelOption)
}

struct HistoryPane: View {
    @Bindable var viewModel: SettingsViewModel
    @State private var searchText = ""
    @State private var playback = HistoryPlaybackModel()

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                if filteredDays.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(filteredDays) { day in
                                Section {
                                    ForEach(day.entries) { entry in
                                        HistoryRecordingCard(
                                            entry: entry,
                                            transcript: viewModel.transcriptText(for: entry),
                                            audioURL: viewModel.historyAudioURL(for: entry),
                                            isFailed: viewModel.historyEntryFailed(entry),
                                            isReprocessing: viewModel.reprocessingHistoryEntryID == entry.id,
                                            playback: playback,
                                            onCopy: { viewModel.copyHistoryEntry(entry) },
                                            onReprocess: {
                                                Task { await viewModel.reprocessHistoryEntry(entry) }
                                            }
                                        )
                                    }
                                } header: {
                                    Text(dayTitle(day))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.leading, 4)
                                }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .frame(maxWidth: 500, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 22)

            HistorySearchField(text: $searchText)
                .frame(maxWidth: 360)
                .padding(.horizontal, 26)
                .padding(.bottom, 12)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            viewModel.refreshHistory()
        }
    }

    private var filteredDays: [TranscriptHistoryDay] {
        viewModel.historyDays(matching: searchText)
    }

    @ViewBuilder
    private var emptyState: some View {
        if searchText.isEmpty {
            ContentUnavailableView(
                "No Recordings",
                systemImage: "waveform",
                description: Text("Your saved recordings will appear here.")
            )
        } else {
            ContentUnavailableView.search(text: searchText)
        }
    }

    private func dayTitle(_ day: TranscriptHistoryDay) -> String {
        guard let date = day.entries.first?.timestamp else { return day.day }
        if Calendar.current.isDateInToday(date) {
            return "Today"
        }
        if Calendar.current.isDateInYesterday(date) {
            return "Yesterday"
        }
        return date.formatted(.dateTime.weekday(.wide).month(.wide).day())
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
    @State private var historyAlert: HistoryAlert?

    var body: some View {
        SettingsPaneLayout(tab: .advanced) {
            SettingsPanelSection(title: "Storage") {
                SettingsControlRow(
                    title: "Save History",
                    description: "Choose what Petal keeps after transcription.",
                    symbol: "archivebox"
                ) {
                    SettingsMenuPicker(
                        values: HistoryRetentionMode.allCases,
                        selection: viewModel.historyRetentionMode,
                        title: \.displayName
                    ) { mode in
                        viewModel.historyRetentionModeChanged(mode)
                    }
                }
                SettingsCardDivider()
                SettingsToggleRow(
                    title: "Extra Compression",
                    description: "Use smaller audio files with slightly lower fidelity.",
                    symbol: "arrow.down.right.and.arrow.up.left",
                    isOn: viewModel.compressHistoryAudio
                ) { value in viewModel.$compressHistoryAudio.withLock { $0 = value } }
                SettingsCardDivider()
                SettingsControlRow(
                    title: "History Folder",
                    description: viewModel.historyDirectoryDisplayPath,
                    symbol: "folder"
                ) {
                    SettingsActionButton(title: "Open") {
                        viewModel.openHistoryInFinder()
                    }
                }
            }

            SettingsPanelSection(title: "Maintenance") {
                SettingsControlRow(
                    title: "Remove Saved Audio",
                    description: "Keep transcripts but delete their recording files.",
                    symbol: "waveform.badge.minus"
                ) {
                    SettingsActionButton(title: "Delete…", tint: .red) {
                        historyAlert = .deleteMedia
                    }
                }

                SettingsCardDivider()

                SettingsControlRow(
                    title: "Reset History",
                    description: "Permanently delete transcripts and saved audio.",
                    symbol: "trash"
                ) {
                    SettingsActionButton(title: "Delete All…", tint: .red) {
                        historyAlert = .deleteAll
                    }
                }
            }

            SettingsPanelSection(title: "Diagnostics") {
                SettingsToggleRow(
                    title: "Diagnostic Logs",
                    description: "Record local details that help troubleshoot Petal.",
                    symbol: "doc.text.magnifyingglass",
                    isOn: viewModel.logsEnabled
                ) { value in viewModel.$logsEnabled.withLock { $0 = value } }
                SettingsCardDivider()
                SettingsControlRow(
                    title: "Export Logs",
                    description: "Save a copy to share while troubleshooting.",
                    symbol: "square.and.arrow.up"
                ) {
                    SettingsActionButton(title: "Export…") {
                        viewModel.exportLogs()
                    }
                    .disabled(!viewModel.canExportLogs)
                }
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
            if let historyAlert {
                Text(historyAlert.message)
            }
        }
    }

    private var isShowingHistoryAlert: Binding<Bool> {
        Binding(get: { historyAlert != nil }, set: {
            if !$0 {
                historyAlert = nil
            }
        })
    }

    private func performHistoryAction(for alert: HistoryAlert) {
        switch alert {
        case .deleteAll: viewModel.deleteAllHistory()
        case .deleteMedia: viewModel.deleteMediaOnly()
        }
    }
}

#Preview("Settings") {
    SettingsView(viewModel: SettingsViewModel(appModel: AppModel.makePreview()))
        .frame(width: 720, height: 680)
}
