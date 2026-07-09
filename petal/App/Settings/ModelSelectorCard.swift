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

    var body: some View {
        Button {
            guard isEnabled else { return }
            action()
        } label: {
            HStack(spacing: 11) {
                iconView

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(isWarming ? .orange : .secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
                trailingAccessory
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selectionBackground)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.55)
        .contextMenu { contextMenuItems }
        .animation(.easeInOut(duration: 0.18), value: isSelected)
        .animation(.easeInOut(duration: 0.18), value: isWarming)
    }

    private var subtitle: String {
        if isWarming { return "Warming up" }
        return [option.providerDisplayName, option.sizeLabel]
            .compactMap { $0 }
            .joined(separator: " · ")
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

    @ViewBuilder
    private var iconView: some View {
        let image = icon
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 24, height: 24)

        if option.provider == .nvidia {
            image
        } else {
            image.clipShape(.rect(cornerRadius: 6))
        }
    }

    @ViewBuilder
    private var selectionBackground: some View {
        if isWarming {
            Color.orange.opacity(0.1)
        } else if isSelected {
            Color.accentColor.opacity(0.1)
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
}
