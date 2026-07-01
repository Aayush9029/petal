import Assets
import Shared
import SwiftUI

struct ModelSelectorCard: View {
    enum DownloadState: Equatable {
        case ready
        case needsDownload
        case preparing
        case downloading(ModelDownloadState.Progress)
        case paused(ModelDownloadState.Progress)
        case failed(String)
    }

    let option: ModelOption
    let isSelected: Bool
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
            HStack(spacing: 12) {
                iconView

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(option.displayName)
                            .font(.headline)
                            .fontDesign(.rounded)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if option.isRecommended {
                            Text("Recommended")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if showsStatusText {
                        Text(statusText)
                            .font(.caption2)
                            .foregroundStyle(statusColor)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                trailingAccessory
            }
            .padding(.vertical, 8)
            .padding(.leading, leadingPadding)
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
            }
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.55)
        .contextMenu {
            contextMenuItems
        }
    }

    private var subtitle: String {
        var parts = [option.descriptor.parameters]
        if let size = option.sizeLabel {
            parts.append(size)
        }
        return parts.joined(separator: " · ")
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
            .frame(width: iconSize, height: iconSize)

        if shouldClipIcon {
            image.clipShape(.rect(cornerRadius: 6))
        } else {
            image
        }
    }

    private var iconSize: CGFloat {
        option.provider == .nvidia ? 26.4 : 24
    }

    private var leadingPadding: CGFloat {
        option.provider == .nvidia ? 18 : 12
    }

    private var shouldClipIcon: Bool {
        option.provider != .nvidia
    }

    @ViewBuilder
    private var trailingAccessory: some View {
        switch downloadState {
        case .ready:
            if isSelected {
                pillAccessory(.active)
            } else {
                pillAccessory(.use)
            }
        case .needsDownload:
            pillAccessory(.get)
        case .preparing:
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.6)
                .frame(width: 24, height: 24)
        case let .downloading(progress):
            circularProgress(progress.fraction)
        case .paused:
            Image(systemName: "pause.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 24)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.red)
                .frame(width: 24, height: 24)
        }
    }

    private var statusText: String {
        switch downloadState {
        case .ready:
            return isSelected ? "Active" : "Ready"
        case .needsDownload:
            return "Not downloaded"
        case .preparing:
            return "Preparing download"
        case let .downloading(progress):
            return "Downloading · \(progress.summaryText)"
        case let .paused(progress):
            return "Paused · \(progress.summaryText)"
        case let .failed(message):
            return message
        }
    }

    private var statusColor: Color {
        switch downloadState {
        case .ready:
            return isSelected ? .accentColor : .secondary
        case .needsDownload, .preparing, .downloading, .paused:
            return .secondary
        case .failed:
            return .red
        }
    }

    private var showsStatusText: Bool {
        switch downloadState {
        case .ready, .needsDownload:
            return false
        case .preparing, .downloading, .paused, .failed:
            return true
        }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        switch downloadState {
        case .ready where option.requiresDownload:
            if let onDeleteDownloadedModel {
                Button(role: .destructive) {
                    onDeleteDownloadedModel()
                } label: {
                    Label("Delete Download…", systemImage: "trash")
                }
            }
        case .downloading:
            if let onPauseDownload {
                Button {
                    onPauseDownload()
                } label: {
                    Label("Pause Download", systemImage: "pause.circle")
                }
            }
            if let onCancelDownload {
                Button(role: .destructive) {
                    onCancelDownload()
                } label: {
                    Label("Cancel Download", systemImage: "xmark.circle")
                }
            }
        case .paused:
            if let onResumeDownload {
                Button {
                    onResumeDownload()
                } label: {
                    Label("Resume Download", systemImage: "play.circle")
                }
            }
            if let onCancelDownload {
                Button(role: .destructive) {
                    onCancelDownload()
                } label: {
                    Label("Cancel Download", systemImage: "xmark.circle")
                }
            }
        default:
            EmptyView()
        }
    }

    private enum AccessoryPillStyle {
        case active
        case get
        case use

        var title: String {
            switch self {
            case .active:
                return "Active"
            case .get:
                return "Get"
            case .use:
                return "Use"
            }
        }

        var foregroundColor: Color {
            switch self {
            case .active, .get:
                return .white
            case .use:
                return .black
            }
        }

        var backgroundColor: Color {
            switch self {
            case .active:
                return .black
            case .get:
                return .accentColor
            case .use:
                return .white
            }
        }

        var borderColor: Color {
            switch self {
            case .active:
                return .black
            case .get:
                return .accentColor
            case .use:
                return Color(nsColor: .separatorColor)
            }
        }
    }

    private func pillAccessory(_ style: AccessoryPillStyle) -> some View {
        Text(style.title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(style.foregroundColor)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(minWidth: 54, minHeight: 24)
            .background(style.backgroundColor, in: .capsule)
            .overlay {
                Capsule()
                    .strokeBorder(style.borderColor, lineWidth: 1)
            }
    }

    private func circularProgress(_ progress: Double) -> some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.24), lineWidth: 4.2)
            Circle()
                .trim(from: 0, to: max(0.03, min(1, progress)))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4.2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 17.4, height: 17.4)
        .animation(.linear(duration: 0.15), value: progress)
    }
}
