import Assets
import Shared
import SwiftUI

struct ModelInfoRow: View {
    let option: ModelOption

    var body: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                providerIcon
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                if option.provider == .voxtralCore {
                    Image.appleIntelligence
                        .resizable()
                        .scaledToFill()
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(.black.opacity(0.4), lineWidth: 1)
                        )
                        .offset(x: 2, y: 2)
                }
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(option.displayName)
                    .font(.headline)

                Text(option.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 12) {
                    ratingView(
                        icon: "bolt.fill",
                        score: option.descriptor.speedScore,
                        color: .orange,
                        label: "Speed"
                    )
                    ratingView(
                        icon: "sparkle",
                        score: option.descriptor.smartScore,
                        color: .yellow,
                        label: "Accuracy"
                    )

                    if let sizeLabel = option.sizeLabel {
                        Text(sizeLabel)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private func ratingView(icon: String, score: Int, color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .foregroundStyle(.secondary)
            ForEach(0 ..< 5, id: \.self) { i in
                Image(systemName: icon)
                    .foregroundStyle(i < score ? AnyShapeStyle(color) : AnyShapeStyle(.tertiary))
            }
        }
        .font(.system(size: 9))
    }

    private var providerIcon: Image {
        switch option.provider {
        case .appleSpeech: .swiftLogo
        case .fluidAudio: .qwen
        case .nvidia: .nvidia
        case .whisperKit: .openai
        case .cohere: .cohere
        case .voxtralCore: .mistral
        }
    }
}
