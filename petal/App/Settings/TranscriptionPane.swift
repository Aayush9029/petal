import AppFeature
import ModelDownloadFeature
import Shared
import SwiftUI

struct TranscriptionPane: View {
    @Bindable var viewModel: SettingsViewModel
    @State private var modelPendingDeletion: ModelOption?

    var body: some View {
        SettingsPaneLayout {
            SettingsSection(title: "Speech Model") {
                SettingsGlassContainer {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                        ForEach(viewModel.visibleModelOptions) { option in
                            modelCard(for: option)
                        }
                    }
                }
            }

        }
        .alert(item: $modelPendingDeletion) { option in
            Alert(
                title: Text("Delete Download"),
                message: Text("Remove \(option.displayName) from this Mac? You can download it again later."),
                primaryButton: .destructive(Text("Delete")) { Task { await viewModel.deleteDownloadedModel(option) } },
                secondaryButton: .cancel()
            )
        }
    }

    private func modelCard(for option: ModelOption) -> some View {
        ModelSelectorCard(
            option: option,
            isSelected: viewModel.selectedModelID == option.rawValue,
            isWarming: viewModel.selectedModelID == option.rawValue && viewModel.isWarmingModel,
            downloadState: viewModel.downloadState(for: option),
            onDeleteDownloadedModel: { modelPendingDeletion = option },
            onPauseDownload: { viewModel.downloadModel.pauseButtonTapped() },
            onResumeDownload: { Task { await viewModel.downloadModel.resumeButtonTapped() } },
            onCancelDownload: { viewModel.downloadModel.cancelButtonTapped() }
        ) {
            Task { await viewModel.modelOptionTapped(option) }
        }
    }
}
