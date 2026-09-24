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
            }
            .task { viewModel.cleanupDownloads.task() }
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

            if viewModel.cleanupModel == .s1Mini {
                SettingsPanelSection(title: "S1-mini Output") {
                    S1MiniControlsForm(
                        controls: S1MiniControls(
                            styling: viewModel.s1MiniStyling,
                            structure: viewModel.s1MiniStructure,
                            context: viewModel.s1MiniContext
                        ),
                        onStylingChange: { value in viewModel.$s1MiniStyling.withLock { $0 = value } },
                        onStructureChange: { value in viewModel.$s1MiniStructure.withLock { $0 = value } },
                        onContextChange: { value in viewModel.$s1MiniContext.withLock { $0 = value } }
                    )
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))

                SettingsPanelSection(title: "S1-mini System Prompt") {
                    PromptEditor(
                        text: Binding(viewModel.$s1MiniSystemPrompt),
                        defaultText: S1MiniControls.defaultSystemPrompt,
                        minHeight: 90,
                        note: "S1-mini was trained on the default prompt. Other wording can garble the output."
                    )
                }
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

    private func card(for model: CleanupModel) -> some View {
        CleanupModelCard(
            model: model,
            isSelected: viewModel.cleanupModel == model,
            downloadState: viewModel.cleanupDownloads[model]?.state,
            sizeLabel: viewModel.cleanupDownloads[model]?.sizeLabel,
            onCancelDownload: { viewModel.cleanupDownloads[model]?.cancelButtonTapped() },
            onDeleteDownload: { modelPendingDelete = model }
        ) {
            Task { await viewModel.cleanupModelTapped(model) }
        }
    }
}
