import ModelDownloadFeature
import Shared
import SwiftUI

struct IntelligencePane: View {
    @Bindable var viewModel: SettingsViewModel
    @State private var isConfirmingS1MiniDelete = false

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
            .task { viewModel.s1MiniDownload.task() }
            .confirmationDialog("Delete S1-mini?", isPresented: $isConfirmingS1MiniDelete) {
                Button("Delete", role: .destructive) {
                    Task { await viewModel.s1MiniDownload.deleteButtonTapped() }
                }
            } message: {
                Text("Cleanup turns off until you download S1-mini again.")
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
            downloadState: model == .s1Mini ? viewModel.s1MiniDownload.state : nil,
            sizeLabel: model == .s1Mini ? viewModel.s1MiniDownload.sizeLabel : nil,
            onCancelDownload: { viewModel.s1MiniDownload.cancelButtonTapped() },
            onDeleteDownload: { isConfirmingS1MiniDelete = true }
        ) {
            Task { await viewModel.cleanupModelTapped(model) }
        }
    }
}
