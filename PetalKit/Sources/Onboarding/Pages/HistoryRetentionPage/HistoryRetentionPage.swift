import Shared
import SwiftUI
import UI

struct HistoryRetentionPage: View {
    @Bindable var model: OnboardingModel
    @State private var isAnimating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            cards
        }
        .onAppear { isAnimating = true }
    }

    private var header: some View {
        OnboardingHeader(
            symbol: "clock.arrow.trianglehead.counterclockwise.rotate.90",
            title: "Choose What to Keep",
            description: "Everything stays on your device — nothing is ever sent to a server. Choose what Petal keeps after each transcription.",
            layout: .vertical
        )
        .slideIn(active: isAnimating, delay: 0.25)
    }

    private var cards: some View {
        HStack(alignment: .top, spacing: 12) {
            OnboardingChoiceCard(
                symbol: "doc.text",
                title: "Text Only",
                description: "Save the transcription text. Audio is not stored.",
                isSelected: model.historyRetentionMode == .transcripts
            ) { model.$historyRetentionMode.withLock { $0 = .transcripts } }

            OnboardingChoiceCard(
                symbol: "doc.text.below.ecg",
                title: "Everything",
                description: "Keep audio recordings and transcription text.",
                recommended: true,
                isSelected: model.historyRetentionMode == .both
            ) { model.$historyRetentionMode.withLock { $0 = .both } }

            OnboardingChoiceCard(
                symbol: "hand.raised.fill",
                title: "Private",
                description: "Nothing is saved. Transcriptions are pasted and discarded.",
                isSelected: model.historyRetentionMode == .none
            ) { model.$historyRetentionMode.withLock { $0 = .none } }
        }
        .frame(height: 220)
        .slideIn(active: isAnimating, delay: 0.5)
    }
}

#Preview("History Retention") {
    OnboardingView(model: .makePreview(page: .historyRetention))
}

#Preview("History Retention - Off") {
    OnboardingView(model: .makePreview(page: .historyRetention) { model in
        model.$historyRetentionMode.withLock { $0 = .none }
    })
}

#Preview("History Retention - Transcripts") {
    OnboardingView(model: .makePreview(page: .historyRetention) { model in
        model.$historyRetentionMode.withLock { $0 = .transcripts }
    })
}
