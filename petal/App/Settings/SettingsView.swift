import Assets
import KeyboardShortcuts
import ModelDownloadFeature
import Shared
import SwiftUI
import UI

// MARK: - Settings Root

struct SettingsView: View {
    @State var selectedTab: SettingsTab = .general
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("General", systemImage: "gearshape", value: .general) {
                GeneralPane(viewModel: viewModel)
            }
            Tab("Transcription", systemImage: "waveform", value: .transcription) {
                TranscriptionPane(viewModel: viewModel)
            }
            Tab("History", systemImage: "clock", value: .history) {
                HistoryPane(viewModel: viewModel)
            }
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
        .task {
            await viewModel.refreshPermissions()
        }
    }
}

// MARK: - Transcription Pane

struct TranscriptionPane: View {
    @Bindable var viewModel: SettingsViewModel
    @State private var showDeleteConfirmation = false

    var body: some View {
        Form {
            Section("Model") {
                Picker("Model", selection: Binding(
                    get: { viewModel.selectedModelID },
                    set: { viewModel.selectedModelID = $0 }
                )) {
                    ForEach(ModelOption.allCases) { option in
                        HStack {
                            providerIcon(for: option)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 12, height: 12)
                                .clipShape(.rect(cornerRadius: 3))
                            Text(option.displayName)
                            if option.isRecommended {
                                Text("Recommended")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(option.rawValue)
                    }
                }

                if let selectedModel = viewModel.downloadModel.selectedModelOption {
                    if let size = selectedModel.sizeLabel {
                        LabeledContent("Size") {
                            Text(size)
                        }
                    }
                    modelDownloadStatus
                }

                if viewModel.isWarmingModel {
                    HStack(spacing: 8) {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(.orange)
                        Text("Warming up…")
                            .foregroundStyle(.secondary)
                    }
                    .shimmering()
                }
            }

            Section("Audio Preprocessing") {
                Toggle("Trim silence", isOn: Binding(viewModel.$trimSilenceEnabled))
                Text("Removes silent segments from the start and end of your recording.")
                    .settingDescription()
                Toggle("Auto speed-up", isOn: Binding(viewModel.$autoSpeedEnabled))
                Text("Speeds up quiet or low-energy audio to reduce transcription time.")
                    .settingDescription()
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
        .alert("Delete Model", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                Task { await viewModel.deleteModelButtonTapped() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the downloaded model from your device. You can re-download it later.")
        }
    }

    private func providerIcon(for option: ModelOption) -> Image {
        switch option.provider {
        case .appleSpeech: .swiftLogo
        case .fluidAudio: .qwen
        case .nvidia: .nvidia
        case .whisperKit: .openai
        case .voxtralCore: .mistral
        }
    }

    @ViewBuilder
    private var modelDownloadStatus: some View {
        if let selectedModel = viewModel.downloadModel.selectedModelOption, !selectedModel.requiresDownload {
            LabeledContent("Status") {
                Label("Ready (No download required)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        } else {
            switch viewModel.downloadModel.state {
            case .downloaded:
                LabeledContent("Status") {
                    Label("Downloaded", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                Button("Delete Model", role: .destructive) {
                    showDeleteConfirmation = true
                }
            case let .downloading(progress):
                downloadProgressSection(progress: progress, isPaused: false)
            case let .paused(progress):
                downloadProgressSection(progress: progress, isPaused: true)
            case .notDownloaded, .preparing:
                Button("Download Model") {
                    Task { await viewModel.downloadButtonTapped() }
                }
            case let .failed(message):
                Button("Download Model") {
                    Task { await viewModel.downloadButtonTapped() }
                }
                Text(message)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
    }

    @ViewBuilder
    private func downloadProgressSection(progress: ModelDownloadState.Progress, isPaused: Bool) -> some View {
        let modelName = viewModel.downloadModel.downloadingModelOption?.displayName
            ?? viewModel.downloadModel.selectedModelOption?.displayName ?? "model"
        HStack(spacing: 12) {
            ProgressView(value: progress.fraction)
                .progressViewStyle(.circular)
                .scaleEffect(0.5)
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text("Downloading \(modelName)")
                Text(progress.summaryText)
                    .settingDescription()
            }
        }
        HStack {
            if isPaused {
                Button("Resume") {
                    Task { await viewModel.resumeButtonTapped() }
                }
            } else {
                Button("Pause") {
                    viewModel.pauseButtonTapped()
                }
            }

            Button("Cancel") {
                viewModel.cancelButtonTapped()
            }
        }
    }
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
}

#Preview("Settings") {
    SettingsView(viewModel: SettingsViewModel(appModel: AppModel.makePreview()))
        .frame(width: 640, height: 520)
}
