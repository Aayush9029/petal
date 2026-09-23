import Shared
import SwiftUI
import UI

struct OnboardingChoiceCard: View {
    var symbol: String
    /// Replaces the symbol with a brand icon.
    var image: Image?
    var title: String
    var description: String
    var recommended = false
    var isSelected: Bool
    var onSelect: () -> Void

    @State private var isHovering = false

    // MARK: - Computed

    private var borderColor: Color {
        isSelected ? Color.white.opacity(0.6) : Color.white.opacity(0.15)
    }

    private var borderWidth: CGFloat {
        isSelected ? 2 : 1
    }

    private var checkmarkIcon: String {
        isSelected ? "checkmark.circle.fill" : "circle"
    }

    // MARK: - Body

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                symbolImage
                titleLabel
                descriptionLabel
                Spacer(minLength: 0)
            }
            .padding(20)
            .xSpacing(.topLeading)
            .foregroundStyle(.white)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.black))
            .overlay(alignment: .bottomTrailing) { checkmark }
            .overlay { border }
            .overlay(alignment: .topTrailing) {
                if recommended {
                    RecommendedBadge()
                        .padding(.trailing, 8)
                        .offset(y: -10)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovering ? 1.04 : 1.0)
        .animation(.easeOut(duration: 0.2), value: isHovering)
        .onHover { isHovering = $0 }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var symbolImage: some View {
        if let image {
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 40, height: 40)
                .clipShape(.rect(cornerRadius: 10))
                .padding(.bottom, 8)
        } else {
            symbolView
        }
    }

    private var symbolView: some View {
        Image(systemName: symbol)
            .font(.largeTitle)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(isSelected ? .white : .secondary)
            .frame(width: 40, height: 40)
            .padding(.bottom, 8)
    }

    private var titleLabel: some View {
        Text(title)
            .font(.title3.weight(.semibold))
    }

    private var descriptionLabel: some View {
        Text(description)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var checkmark: some View {
        Image(systemName: checkmarkIcon)
            .font(.body)
            .foregroundStyle(isSelected ? .white : Color.white.opacity(0.2))
            .padding(14)
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: 14)
            .strokeBorder(borderColor, lineWidth: borderWidth)
    }
}

// MARK: - Previews

#Preview("Selected") {
    OnboardingChoiceCard(
        symbol: "doc.text.below.ecg",
        title: "Audio + Transcripts",
        description: "Save both audio recordings and transcription text for full history.",
        recommended: true,
        isSelected: true
    ) {}
        .frame(width: 220, height: 220)
        .padding()
        .preferredColorScheme(.dark)
}

#Preview("Unselected") {
    OnboardingChoiceCard(
        symbol: "hand.raised.fill",
        title: "Private",
        description: "Nothing is saved to disk. Transcriptions are pasted to your clipboard and forgotten.",
        isSelected: false
    ) {}
        .frame(width: 220, height: 220)
        .padding()
        .preferredColorScheme(.dark)
}
