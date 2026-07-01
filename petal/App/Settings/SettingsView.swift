import Assets
import AudioClient
import KeyboardShortcuts
import ModelDownloadFeature
import Shared
import SwiftUI
import UI

// MARK: - Settings Root

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: sidebarSelection) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    HStack(spacing: 10) {
                        SettingsTabIcon(tab: tab, size: 20)
                        Text(tab.title)
                    }
                    .tag(tab)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 240)
        } detail: {
            pane
                .navigationTitle(selectedTab.title)
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var sidebarSelection: Binding<SettingsTab?> {
        Binding(get: { selectedTab }, set: { selectedTab = $0 ?? selectedTab })
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

// MARK: - General Pane

struct GeneralPane: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("Shortcut") {
                LabeledContent("Shortcut") {
                    UnifiedShortcutRecorder(shortcut: viewModel.unifiedShortcutBinding)
                }
                Text(viewModel.shortcutDescription)
                    .settingDescription()

                LabeledContent("Hold Duration") {
                    Picker("Hold Duration", selection: Binding(viewModel.$pushToTalkThreshold)) {
                        ForEach(PushToTalkThreshold.allCases) { threshold in
                            Text(threshold.displayName).tag(threshold)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                    .labelsHidden()
                }
            }

            Section("Permissions") {
                LabeledContent("Microphone") {
                    if viewModel.microphoneAuthorized {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Grant Access") {
                            Task { await viewModel.grantMicrophonePermissionButtonTapped() }
                        }
                    }
                }

                LabeledContent("Accessibility") {
                    if viewModel.accessibilityAuthorized {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Grant Access") {
                            Task { await viewModel.grantAccessibilityPermissionButtonTapped() }
                        }
                    }
                }

                if let message = viewModel.permissionMessage {
                    Text(message)
                        .settingDescription()
                }
            }
        }
        .formStyle(.grouped)
        .task {
            await viewModel.refreshPermissions()
        }
    }
}

// MARK: - Advanced Pane

struct AdvancedPane: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("Diagnostics") {
                Toggle("Enable logs", isOn: Binding(viewModel.$logsEnabled))
                Text("Disabled by default to avoid creating log files unless you explicitly turn this on.")
                    .settingDescription()

                Button("Export Logs…") {
                    viewModel.exportLogs()
                }
                .disabled(!viewModel.canExportLogs)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Recording Pane

struct RecordingPane: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("Input") {
                Picker("Microphone", selection: Binding(
                    get: { viewModel.selectedAudioInputID },
                    set: { viewModel.selectedAudioInputID = $0 }
                )) {
                    ForEach(viewModel.audioInputDevices) { device in
                        Text(device.name).tag(device.id)
                    }
                }
                Text("Petal falls back to the system default microphone if the selected device is unavailable.")
                    .settingDescription()
            }

            Section("Audio Preprocessing") {
                Toggle("Trim silence", isOn: Binding(viewModel.$trimSilenceEnabled))
                Text("Removes silent segments from the start and end of your recording.")
                    .settingDescription()
                Toggle("Auto speed-up", isOn: Binding(viewModel.$autoSpeedEnabled))
                Text("Speeds up quiet or low-energy audio to reduce transcription time.")
                    .settingDescription()
            }

            Section("Clipboard") {
                Toggle("Restore clipboard after paste", isOn: Binding(viewModel.$restoreClipboardAfterPaste))
                Text("When enabled, Petal restores your previous clipboard contents after auto-pasting.")
                    .settingDescription()
            }

            Section("System Audio") {
                Toggle("Lower system volume while recording", isOn: Binding(viewModel.$duckSystemAudioDuringRecording))
                Text("Reduces system output volume during dictation and restores it afterward.")
                    .settingDescription()
            }
        }
        .formStyle(.grouped)
        .task {
            await viewModel.refreshAudioInputDevices()
        }
    }
}

// MARK: - Transcription Pane

struct TranscriptionPane: View {
    @Bindable var viewModel: SettingsViewModel
    @State private var destination: TranscriptionDestination?

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    if let pinnedDownloadOption = viewModel.pinnedDownloadOption {
                        modelCard(for: pinnedDownloadOption)
                            .padding(.bottom, 4)
                    }

                    ForEach(viewModel.modelProviderGroups) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.leading, 4)

                            ForEach(group.options) { option in
                                modelCard(for: option)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if viewModel.isWarmingModel {
                        warmingStatus
                    }
                }
                .modelSectionRowStyle()
            }

            Section {
                if viewModel.appleIntelligenceAvailable {
                    Toggle("Enhance with Apple Intelligence", isOn: Binding(viewModel.$appleIntelligenceEnabled))
                    Text("Post-process transcriptions on-device to fix grammar, punctuation, and formatting. Enables Smart mode for all models.")
                        .settingDescription()
                } else {
                    LabeledContent("Status") {
                        Text("Unavailable")
                            .foregroundStyle(.secondary)
                    }
                    Text("Requires macOS 26 with Apple Intelligence enabled.")
                        .settingDescription()
                }
            } header: {
                HStack(spacing: 6) {
                    Image.appleIntelligence
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    Text("Apple Intelligence")
                }
            }

            if viewModel.smartModeAvailable {
                Section("Mode") {
                    Picker("Transcription Mode", selection: Binding(viewModel.$transcriptionMode)) {
                        ForEach(TranscriptionMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(viewModel.transcriptionMode.description)
                        .settingDescription()
                }

                if viewModel.transcriptionMode == .smart {
                    Section("Smart Prompt") {
                        TextField("Prompt", text: Binding(viewModel.$smartPrompt), axis: .vertical)
                            .lineLimit(3 ... 6)
                    }
                }
            }
        }
        .formStyle(.grouped)
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
            Button("Cancel", role: .cancel) {
                destination = nil
            }
        } message: { option in
            Text("Remove \(option.displayName) from this Mac? You can download it again later.")
        }
    }

    private func modelCard(for option: ModelOption) -> some View {
        ModelSelectorCard(
            option: option,
            isSelected: viewModel.selectedModelID == option.rawValue,
            downloadState: downloadState(for: option),
            isEnabled: !viewModel.downloadModel.isDeletingModel(option),
            onDeleteDownloadedModel: {
                destination = .deleteModel(option)
            },
            onPauseDownload: {
                viewModel.pauseButtonTapped()
            },
            onResumeDownload: {
                Task { await viewModel.resumeButtonTapped() }
            },
            onCancelDownload: {
                viewModel.cancelButtonTapped()
            }
        ) {
            if let option = viewModel.modelOptionTapped(option) {
                Task {
                    await viewModel.downloadModelConfirmed(option)
                }
            }
        }
    }

    private var warmingStatus: some View {
        HStack(spacing: 12) {
            Image(systemName: "flame.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Warming up")
                    .font(.subheadline.weight(.medium))
                Text("Petal is loading the selected model.")
                    .settingDescription()
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 12))
        .shimmering()
    }

    private func downloadState(for option: ModelOption) -> ModelSelectorCard.DownloadState {
        guard option.requiresDownload else { return .ready }
        guard !viewModel.downloadModel.isDeletingModel(option) else { return .deleting }

        let state = viewModel.downloadModel.state
        let isDownloadingOption = viewModel.downloadModel.downloadingModelOption == option

        if isDownloadingOption {
            switch state {
            case .downloaded:
                return .ready
            case .notDownloaded:
                break
            case .preparing:
                return .preparing
            case let .downloading(progress):
                return .downloading(progress)
            case let .paused(progress):
                return .paused(progress)
            case let .failed(message):
                return .failed(message)
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
            set: { isPresented in
                if !isPresented {
                    destination = nil
                }
            }
        )
    }
}

private enum TranscriptionDestination {
    case deleteModel(ModelOption)
}

// MARK: - History Pane

struct HistoryPane: View {
    @Bindable var viewModel: SettingsViewModel
    @State private var historyAlert: HistoryAlert?

    var body: some View {
        Form {
            if !viewModel.recentHistoryEntries.isEmpty {
                Section("Recent") {
                    ForEach(viewModel.recentHistoryEntries) { entry in
                        let transcript = viewModel.transcriptText(for: entry)
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(transcript)
                                    .lineLimit(2)
                                    .truncationMode(.tail)
                                Text(entry.timestamp, style: .relative)
                                    .settingDescription()
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
                    }
                }
            }

            Section("Retention") {
                Picker("Keep", selection: Binding(
                    get: { viewModel.historyRetentionMode },
                    set: { viewModel.historyRetentionModeChanged($0) }
                )) {
                    ForEach(HistoryRetentionMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            }

            Section("Compression") {
                Toggle("Extra compression", isOn: Binding(viewModel.$compressHistoryAudio))
                Text("History audio is saved as AAC (.m4a) by default. Enable for lower-bitrate files.")
                    .settingDescription()
            }

            Section("Storage") {
                LabeledContent("Location") {
                    Text(viewModel.historyDirectoryPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Button("Open in Finder") {
                    viewModel.openHistoryInFinder()
                }
            }

            Section("Clear Data") {
                HStack(spacing: 12) {
                    Button("Delete All History & Media", role: .destructive) {
                        historyAlert = .deleteAll
                    }
                    .frame(maxWidth: .infinity)

                    Button("Delete Media Only", role: .destructive) {
                        historyAlert = .deleteMedia
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .formStyle(.grouped)
        .alert(historyAlert?.title ?? "", isPresented: isShowingHistoryAlert) {
            if let historyAlert {
                Button(historyAlert.confirmTitle, role: .destructive) {
                    performHistoryAction(for: historyAlert)
                    self.historyAlert = nil
                }
            }
            Button("Cancel", role: .cancel) {
                historyAlert = nil
            }
        } message: {
            if let historyAlert {
                Text(historyAlert.message)
            }
        }
    }

    private var isShowingHistoryAlert: Binding<Bool> {
        Binding(
            get: { historyAlert != nil },
            set: { isPresented in
                if !isPresented {
                    historyAlert = nil
                }
            }
        )
    }

    private func performHistoryAction(for alert: HistoryAlert) {
        switch alert {
        case .deleteAll:
            viewModel.deleteAllHistory()
        case .deleteMedia:
            viewModel.deleteMediaOnly()
        }
    }
}

private enum HistoryAlert {
    case deleteAll
    case deleteMedia

    var title: String {
        switch self {
        case .deleteAll:
            return "Delete All History & Media"
        case .deleteMedia:
            return "Delete Media Only"
        }
    }

    var confirmTitle: String {
        switch self {
        case .deleteAll:
            return "Delete All"
        case .deleteMedia:
            return "Delete Media"
        }
    }

    var message: String {
        switch self {
        case .deleteAll:
            return "This will permanently delete all transcription history, audio files, and transcript files."
        case .deleteMedia:
            return "This will delete all saved audio files but keep your transcription history intact."
        }
    }
}

// MARK: - Helpers

private extension View {
    func settingDescription() -> some View {
        font(.caption)
            .foregroundStyle(.secondary)
    }

    func modelSectionRowStyle() -> some View {
        listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

#Preview("Settings") {
    SettingsView(viewModel: SettingsViewModel(appModel: AppModel.makePreview()))
        .frame(width: 740, height: 680)
}
