import Assets
import Shared
import SwiftUI

struct ModelSelectorCard: View {
    enum DownloadState: Equatable {
        case ready
        case needsDownload
        case deleting
        case preparing
        case downloading(ModelDownloadState.Progress)
        case paused(ModelDownloadState.Progress)
        case failed(String)
    }

    let option: ModelOption
    let isSelected: Bool
    var isWarming = false
    let downloadState: DownloadState
    var isEnabled = true
    var onDeleteDownloadedModel: (() -> Void)?
    var onPauseDownload: (() -> Void)?
    var onResumeDownload: (() -> Void)?
    var onCancelDownload: (() -> Void)?
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button {
            guard isEnabled else { return }
            action()
        } label: {
            HStack(spacing: 12) {
                iconView

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(option.displayName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)

                        if option.isRecommended {
                            Text("Recommended")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 7)
                                .frame(height: 17)
                                .background(Color.accentColor.opacity(0.1), in: .capsule)
                        }
                    }

                    Text(compactSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    HStack(spacing: 9) {
                        Text(metadata)
                            .foregroundStyle(isWarming ? Color.orange : Color.secondary.opacity(0.72))

                        scoreMeter(.speed, score: option.descriptor.speedScore)
                        scoreMeter(.intelligence, score: option.descriptor.smartScore)
                    }
                    .font(.caption2)
                }

                Spacer(minLength: 8)
                trailingAccessory
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selectionBackground)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.55)
        .contextMenu { contextMenuItems }
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.18), value: isSelected)
        .animation(.easeInOut(duration: 0.18), value: isWarming)
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    private var metadata: String {
        if isWarming {
            return "Warming up"
        }
        return [option.providerDisplayName, option.sizeLabel]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var compactSummary: String {
        switch option {
        case .appleSpeech: "Built-in, private transcription."
        case .qwen3ASR06B4bit: "Fast multilingual transcription."
        case .parakeetTDT06BV3: "Accurate multilingual dictation."
        case .parakeetTDT06BV2: "Fast English-only dictation."
        case .parakeetTDTCTC110M: "Lightweight, instant English dictation."
        case .whisperLargeV3Turbo: "High-quality transcription in 99 languages."
        case .whisperTiny: "Small, fast multilingual transcription."
        case .mini3b: "Smart speech recognition with richer context."
        case .mini3b8bit: "A smaller smart model with lower memory use."
        }
    }

    private var icon: Image {
        switch option.provider {
        case .appleSpeech: .swiftLogo
        case .fluidAudio: .qwen
        case .nvidia: .nvidia
        case .whisperKit: .openai
        case .voxtralCore: .mistral
        }
    }

    private var iconView: some View {
        icon
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 28, height: 28)
            .clipShape(.rect(cornerRadius: 7))
    }

    @ViewBuilder
    private var selectionBackground: some View {
        if isWarming {
            Color.orange.opacity(0.1)
        } else if isSelected {
            Color.accentColor.opacity(0.09)
        } else if isHovering {
            Color.primary.opacity(0.045)
        }
    }

    @ViewBuilder
    private var trailingAccessory: some View {
        switch downloadState {
        case .ready:
            if isWarming {
                ProgressView()
                    .controlSize(.small)
                    .tint(.orange)
            } else if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            } else {
                Text("Ready")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        case .needsDownload:
            Text("Get")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 24)
                .background(Color.accentColor, in: .capsule)
        case .deleting, .preparing:
            ProgressView()
                .controlSize(.small)
        case let .downloading(progress):
            circularProgress(progress.fraction)
        case .paused:
            Image(systemName: "pause.circle.fill")
                .foregroundStyle(Color.accentColor)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        switch downloadState {
        case .ready where option.requiresDownload:
            if let onDeleteDownloadedModel {
                Button("Delete Download…", systemImage: "trash", role: .destructive) {
                    onDeleteDownloadedModel()
                }
            }
        case .downloading:
            if let onPauseDownload {
                Button("Pause Download", systemImage: "pause.circle", action: onPauseDownload)
            }
            if let onCancelDownload {
                Button("Cancel Download", systemImage: "xmark.circle", role: .destructive, action: onCancelDownload)
            }
        case .paused:
            if let onResumeDownload {
                Button("Resume Download", systemImage: "play.circle", action: onResumeDownload)
            }
            if let onCancelDownload {
                Button("Cancel Download", systemImage: "xmark.circle", role: .destructive, action: onCancelDownload)
            }
        default:
            EmptyView()
        }
    }

    private func circularProgress(_ progress: Double) -> some View {
        ZStack {
            Circle().stroke(.secondary.opacity(0.24), lineWidth: 3.5)
            Circle()
                .trim(from: 0, to: max(0.03, min(1, progress)))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 18, height: 18)
        .animation(.linear(duration: 0.15), value: progress)
    }

    private func scoreMeter(_ kind: ScoreKind, score: Int) -> some View {
        HStack(spacing: 3) {
            scoreIcon(kind)
            meterBars(kind, score: score)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind.title): \(score) out of 5")
        .help("\(kind.title): \(score) out of 5")
    }

    @ViewBuilder
    private func scoreIcon(_ kind: ScoreKind) -> some View {
        if kind == .speed {
            Image(systemName: kind.symbol)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.yellow)
        } else {
            Image(systemName: kind.symbol)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(intelligenceMeterGradient)
        }
    }

    private func meterBars(_ kind: ScoreKind, score: Int) -> some View {
        ZStack {
            meterBarRow(
                activeCount: 5,
                activeColor: Color.secondary.opacity(0.22)
            )

            Group {
                if kind == .speed {
                    Color.yellow
                } else {
                    intelligenceMeterGradient
                }
            }
            .mask { meterBarRow(activeCount: score) }
        }
        .frame(width: 28, height: 9)
    }

    private func meterBarRow(
        activeCount: Int,
        activeColor: Color = .white
    ) -> some View {
        HStack(spacing: 2) {
            ForEach(1 ... 5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(index <= activeCount ? activeColor : .clear)
                    .frame(width: 4, height: 9)
            }
        }
    }

    private var intelligenceMeterGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 1, green: 0.62, blue: 0.22),
                Color(red: 1, green: 0.25, blue: 0.48),
                Color(red: 0.73, green: 0.38, blue: 0.95),
                Color(red: 0.25, green: 0.68, blue: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private enum ScoreKind: Equatable {
        case speed
        case intelligence

        var title: String {
            switch self {
            case .speed: "Speed"
            case .intelligence: "Intelligence"
            }
        }

        var symbol: String {
            switch self {
            case .speed: "hare.fill"
            case .intelligence: "sparkle"
            }
        }
    }
}











