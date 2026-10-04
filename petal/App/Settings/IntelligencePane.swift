import CloudCleanupFeature
import ModelDownloadFeature
import Shared
import SwiftUI

struct IntelligencePane: View {
    @Bindable var viewModel: SettingsViewModel
    @State private var modelPendingDelete: CleanupModel?

    var body: some View {
        SettingsPaneLayout(tab: .intelligence) {
            SettingsPanelSection(title: "Text Cleanup") {
                ForEach(viewModel.cleanupModels) { model in
                    if model != viewModel.cleanupModels.first {
                        SettingsCardDivider()
                    }
                    card(for: model)
                }

                if viewModel.cleanupModel != .off {
                    SettingsCardDivider()
                    minimumWordsRow
                }
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

            if viewModel.showsInstructions {
                SettingsPanelSection(title: "Instructions") {
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

    private var minimumWordsRow: some View {
        SettingsControlRow(
            title: "Minimum Words",
            description: "Shorter dictations, like “OK” or “wow”, paste as you said them."
        ) {
            SettingsSegmentedPicker(
                values: CleanupMinimumWords.allCases,
                selection: viewModel.cleanupMinimumWords,
                title: \.displayName
            ) { value in
                viewModel.$cleanupMinimumWords.withLock { $0 = value }
            }
            .frame(width: 205)
        }
    }

    private func card(for model: CleanupModel) -> some View {
        CleanupModelCard(
            model: model,
            isSelected: viewModel.cleanupModel == model,
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
