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

    @Environment(\.colorSchemeContrast) private var contrast

    private static let cornerRadius: CGFloat = 14

    var body: some View {
        Button {
            guard isEnabled else { return }
            action()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    iconView
                    Spacer(minLength: 8)
                    trailingAccessory
                        .frame(minHeight: 22)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(option.displayName)
                            .font(.body.weight(.semibold))
                            .lineLimit(1)

                        if option.isRecommended {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                                .help("Recommended")
                                .accessibilityLabel("Recommended")
                        }

                        if option.supportsStreamingTranscription {
                            Image(systemName: "text.bubble.fill")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .help("Live transcript")
                                .accessibilityLabel("Live transcript")
                        }
                    }

                    Text(isWarming ? "Warming up" : compactSummary)
                        .font(.caption)
                        .foregroundStyle(isWarming ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                        .lineLimit(2, reservesSpace: true)
                }

                HStack(spacing: 10) {
                    ModelScoreMeter(kind: .speed, score: option.descriptor.speedScore)
                    ModelScoreMeter(kind: .quality, score: option.descriptor.smartScore)
                    Spacer(minLength: 4)
                    sizeChip
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .settingsSelection(isSelected, in: cardShape)
            .overlay {
                cardShape
                    .strokeBorder(borderColor, lineWidth: isSelected || isWarming ? 2 : 1)
            }
            .settingsGlass(in: cardShape)
            .contentShape(.rect(cornerRadius: Self.cornerRadius))
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.55)
        .contextMenu { contextMenuItems }
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityValue(accessibilityState)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(.easeInOut(duration: 0.18), value: isSelected)
        .animation(.easeInOut(duration: 0.18), value: isWarming)
        .animation(.easeInOut(duration: 0.18), value: downloadState)
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
    }

    private var borderColor: Color {
        if isWarming { return .orange }
        if isSelected { return .primary }
        if contrast == .increased { return .primary.opacity(0.6) }
        return .primary.opacity(isHovering ? 0.2 : 0.07)
    }

    @ViewBuilder
    private var sizeChip: some View {
        if let size = option.sizeLabel {
            HStack(spacing: 3) {
                Text(size)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                if isOnDisk {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.primary)
                }
            }
            .font(.caption2.weight(.medium))
            .help(isOnDisk ? "Downloaded" : "Download size")
        }
    }

    private var isOnDisk: Bool {
        option.requiresDownload && downloadState == .ready
    }

    private var accessibilityState: String {
        switch downloadState {
        case .ready:
            if isWarming { return "Warming up" }
            if isSelected { return "Selected" }
            return option.requiresDownload ? "Downloaded" : "Ready"
        case .needsDownload: return "Not downloaded"
        case .deleting: return "Deleting"
        case .preparing: return "Preparing"
        case let .downloading(progress): return "Downloading, \(Int((progress.fraction * 100).rounded())) percent"
        case .paused: return "Paused"
        case let .failed(message): return message
        }
    }

    private var compactSummary: String {
        switch option {
        case .appleSpeech: "Built-in, private transcription."
        case .qwen3ASR17B8bit: "Most accurate multilingual transcription."
        case .parakeetUnified06B: "Live English transcription as you speak."
        case .parakeetTDT06BV3: "Fast dictation in 25 European languages."
        case .parakeetTDTCTC110M: "Lightweight, instant English dictation."
        case .whisperLargeV3Turbo: "High-quality transcription in 99 languages."
        case .mini3b8bit: "A smaller smart model with lower memory use."
        }
    }

    private var icon: Image {
        switch option.provider {
        case .appleSpeech: .swiftLogo
        case .mlxAudio: .qwen
        case .nvidia: .nvidia
        case .whisperKit: .openai
        case .voxtralCore: .mistral
        }
    }

    private var iconView: some View {
        icon
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 34, height: 34)
            .clipShape(.rect(cornerRadius: 9))
            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var trailingAccessory: some View {
        switch downloadState {
        case .ready:
            if isWarming {
                ProgressView()
                    .controlSize(.small)
                    .tint(.orange)
            }
        case .needsDownload:
            Label("Get", systemImage: "arrow.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.background)
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(.primary, in: .capsule)
        case .deleting, .preparing:
            ProgressView()
                .controlSize(.small)
        case let .downloading(progress):
            CircularDownloadProgress(fraction: progress.fraction)
        case .paused:
            Image(systemName: "pause.circle.fill")
                .font(.title3)
                .foregroundStyle(.primary)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.title3)
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
}
