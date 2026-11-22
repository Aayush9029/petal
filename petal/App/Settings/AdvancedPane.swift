import AppFeature
import HistoryClient
import Shared
import SwiftUI

struct AdvancedPane: View {
    @Bindable var viewModel: SettingsViewModel
    @State private var historyAlert: HistoryAlert?

    var body: some View {
        SettingsPaneLayout {
            SettingsPanelSection(title: "Storage") {
                SettingsControlRow(
                    title: "Save History",
                    description: "Choose what Petal keeps after transcription.",
                    symbol: "archivebox",
                    tint: .brown
                ) {
                    SettingsMenuPicker(
                        values: HistoryRetentionMode.allCases,
                        selection: viewModel.history.historyRetentionMode,
                        title: \.displayName
                    ) { mode in
                        viewModel.history.historyRetentionModeChanged(mode)
                    }
                }
                SettingsCardDivider()
                SettingsToggleRow(
                    title: "Extra Compression",
                    description: "Use smaller audio files with slightly lower fidelity.",
                    symbol: "arrow.down.right.and.arrow.up.left",
                    tint: .teal,
                    isOn: viewModel.compressHistoryAudio
                ) { value in viewModel.$compressHistoryAudio.withLock { $0 = value } }
                SettingsCardDivider()
                SettingsControlRow(
                    title: "History Folder",
                    description: viewModel.history.historyDirectoryDisplayPath,
                    symbol: "folder",
                    tint: .blue
                ) {
                    SettingsActionButton(title: "Open") {
                        viewModel.history.openHistoryInFinder()
                    }
                }
            }

            SettingsPanelSection(title: "Maintenance") {
                SettingsControlRow(
                    title: "Remove Saved Audio",
                    description: "Keep transcripts but delete their recording files.",
                    symbol: "waveform.badge.minus",
                    tint: .orange
                ) {
                    SettingsActionButton(title: "Delete…", tint: .red) {
                        historyAlert = .deleteMedia
                    }
                }

                SettingsCardDivider()

                SettingsControlRow(
                    title: "Reset History",
                    description: "Permanently delete transcripts and saved audio.",
                    symbol: "trash",
                    tint: .red
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
                    tint: .gray,
                    isOn: viewModel.logsEnabled
                ) { value in viewModel.$logsEnabled.withLock { $0 = value } }
                SettingsCardDivider()
                SettingsControlRow(
                    title: "Export Logs",
                    description: "Save a copy to share while troubleshooting.",
                    symbol: "square.and.arrow.up",
                    tint: .indigo
                ) {
                    SettingsActionButton(title: "Export…") {
                        viewModel.exportLogs()
                    }
                    .disabled(viewModel.logFileURL == nil)
                }
            }
        }
        .alert(item: $historyAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                primaryButton: .destructive(Text(alert.confirmTitle)) { performHistoryAction(for: alert) },
                secondaryButton: .cancel()
            )
        }
    }

    private func performHistoryAction(for alert: HistoryAlert) {
        switch alert {
        case .deleteAll: viewModel.history.deleteAllHistory()
        case .deleteMedia: viewModel.history.deleteMediaOnly()
        }
    }
}

private enum HistoryAlert: Identifiable {
    var id: Self { self }

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
