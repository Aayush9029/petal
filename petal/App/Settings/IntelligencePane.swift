import CloudCleanupFeature
import ModelDownloadFeature
import Shared
import SwiftUI

struct IntelligencePane: View {
    @Bindable var viewModel: SettingsViewModel
    let onOpenRouter: () -> Void
    @State private var modelPendingDelete: CleanupModel?

    var body: some View {
        SettingsPaneLayout(tab: .intelligence) {
            SettingsPanelSection(title: "Text Cleanup") {
                HStack(spacing: 8) {
                    ForEach(CleanupModel.allCases) { model in
                        tile(for: model)
                    }
                }
                .padding(12)
            }
            .task {
                viewModel.cleanupDownloads.task()
                viewModel.cloudCleanup.task()
            }
            .confirmationDialog(
                "Delete \(modelPendingDelete?.displayName ?? "")?",
                isPresented: Binding(get: { modelPendingDelete != nil }, set: { if !$0 { modelPendingDelete = nil } }),
                presenting: modelPendingDelete
            ) { model in
                Button("Delete", role: .destructive) {
                    Task { await viewModel.cleanupDownloads[model]?.deleteButtonTapped() }
                }
            } message: { model in
                Text("Cleanup turns off until you download \(model.displayName) again.")
            }

            if viewModel.cleanupModel != .off {
                SettingsPanelSection(title: "Minimum Words") {
                    minimumWords
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))

                SettingsPanelSection(title: "Instructions") {
                    SettingsControlRow(
                        title: "Router",
                        description: "Give Mail, Slack, Terminal, or any website its own instructions.",
                        symbol: "arrow.triangle.branch"
                    ) {
                        SettingsActionButton(title: "Open", action: onOpenRouter)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if viewModel.cleanupModel == .cloud {
                CloudCleanupSections(cloud: viewModel.cloudCleanup)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if viewModel.smartModeAvailable {
                SettingsPanelSection(title: "Smart Transcription") {
                    SettingsControlRow(
                        title: "Writing Style",
                        description: "Smart applies your instructions during transcription."
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
                }
            }

            if viewModel.usesSmartTranscription {
                SettingsPanelSection(title: "Smart Instructions") {
                    PromptEditor(
                        text: Binding(viewModel.$smartPrompt),
                        defaultText: TranscriptionMode.defaultSmartPrompt,
                        note: "The default keeps slang, file names, and code terms."
                    )
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.smooth(duration: 0.25), value: viewModel.transcriptionMode)
        .animation(.smooth(duration: 0.25), value: viewModel.cleanupModel)
    }

    private var minimumWords: some View {
        VStack(alignment: .leading, spacing: 11) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Paste As Said")
                    .font(.body.weight(.medium))
                Text("Short dictations, like “OK” or “sounds good”, skip cleanup and paste as you said them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SettingsSegmentedPicker(
                values: CleanupMinimumWords.allCases,
                selection: viewModel.cleanupMinimumWords,
                title: \.displayName
            ) { value in
                viewModel.$cleanupMinimumWords.withLock { $0 = value }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private func tile(for model: CleanupModel) -> some View {
        CleanupModelTile(
            model: model,
            isSelected: viewModel.cleanupModel == model,
            isAvailable: model != .appleIntelligence || viewModel.appleIntelligenceAvailable,
            downloadState: viewModel.cleanupDownloads[model]?.state,
            sizeLabel: viewModel.cleanupDownloads[model]?.sizeLabel,
            detail: model == .cloud ? viewModel.cloudCleanupDetail : nil,
            needsSetup: model == .cloud && !viewModel.cloudCleanup.isConfigured,
            onCancelDownload: { viewModel.cleanupDownloads[model]?.cancelButtonTapped() },
            onDeleteDownload: { modelPendingDelete = model }
        ) {
            Task { await viewModel.cleanupModelTapped(model) }
        }
    }
}
