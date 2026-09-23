import Assets
import Shared
import SwiftUI
import UI

struct CleanupPage: View {
    @Bindable var model: OnboardingModel
    @State private var isAnimating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            OnboardingHeader(
                symbol: "wand.and.sparkles",
                title: "Clean Up Transcripts",
                description: "Remove fillers and false starts, and fix punctuation, on your Mac. Change this later in Settings.",
                layout: .vertical
            )
            .slideIn(active: isAnimating, delay: 0.25)

            VStack(alignment: .leading, spacing: 16) {
                cards
                s1MiniDetails
            }
            .slideIn(active: isAnimating, delay: 0.4)
        }
        .animation(.smooth(duration: 0.25), value: model.cleanupModel)
        .onAppear { isAnimating = true }
        .task { model.s1MiniDownloadModel.task() }
    }

    private var cards: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(model.cleanupModels) { cleanup in
                OnboardingChoiceCard(
                    symbol: symbol(for: cleanup),
                    image: cleanup == .s1Mini ? .superwhisper : nil,
                    title: cleanup.displayName,
                    description: description(for: cleanup),
                    recommended: cleanup == .s1Mini,
                    isSelected: model.cleanupModel == cleanup
                ) { model.cleanupModelTapped(cleanup) }
            }
        }
        .frame(height: 190)
    }

    @ViewBuilder
    private var s1MiniDetails: some View {
        if model.cleanupModel == .s1Mini {
            HStack(spacing: 16) {
                Picker("Style", selection: Binding(model.$s1MiniStyling)) {
                    ForEach(S1MiniStyling.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 320)

                Text(s1MiniStatus)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .transition(.opacity)
        }
    }

    private var s1MiniStatus: String {
        switch model.s1MiniDownloadModel.state {
        case .notDownloaded: "\(model.s1MiniDownloadModel.sizeLabel) download"
        case .preparing: "Preparing download…"
        case let .downloading(progress), let .paused(progress): "Downloading · \(progress.summaryText)"
        case .downloaded: "Ready"
        case let .failed(message): message
        }
    }

    private func symbol(for cleanup: CleanupModel) -> String {
        switch cleanup {
        case .off: "text.alignleft"
        case .appleIntelligence: "apple.intelligence"
        case .s1Mini: "wand.and.sparkles"
        }
    }

    private func description(for cleanup: CleanupModel) -> String {
        switch cleanup {
        case .off: "Paste what you said as is."
        case .appleIntelligence: "Rewrites with your own instructions."
        case .s1Mini: "Removes fillers and formats numbers and dates."
        }
    }
}

#Preview("Cleanup - Off") {
    OnboardingView(model: .makePreview(page: .cleanup) { model in
        model.$cleanupModel.withLock { $0 = .off }
    })
}

#Preview("Cleanup - S1-mini") {
    OnboardingView(model: .makePreview(page: .cleanup) { model in
        model.$cleanupModel.withLock { $0 = .s1Mini }
    })
}
