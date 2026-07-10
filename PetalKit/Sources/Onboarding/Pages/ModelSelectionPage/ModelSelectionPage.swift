import Shared
import SwiftUI
import UI

struct ModelSelectionPage: View {
    @Bindable var model: OnboardingModel
    @State private var isAnimating = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                OnboardingHeader(
                    symbol: "externaldrive.fill",
                    title: "Choose a Model",
                    description: "Transcription runs entirely on-device. Choose between NVIDIA Parakeet, Apple Speech, Qwen, Whisper, and Voxtral model families.",
                    layout: .vertical
                )
                .slideIn(active: isAnimating, delay: 0.25)

                VStack(spacing: 10) {
                    ForEach(ModelOption.allCases) { option in
                        ModelOptionCard(
                            option: option,
                            isSelected: option.rawValue == model.selectedModelID
                        ) {
                            model.selectedModelID = option.rawValue
                        }
                    }
                }
                .slideIn(active: isAnimating, delay: 0.5)
            }
        }
        .scrollIndicators(.hidden)
        .onAppear { isAnimating = true }
    }
}

#Preview("Model Selection") {
    OnboardingView(model: .makePreview(page: .model))
}
