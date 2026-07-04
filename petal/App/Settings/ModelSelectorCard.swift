import Assets
import Shared
import SwiftUI
import UI

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
                        .foregroundStyle(subtitleColor)
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
            .padding(.leading, 12)
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground, in: .rect(cornerRadius: 12))
            .clipShape(.rect(cornerRadius: 12))
            .shimmering(
                active: isWarming,
                gradient: Gradient(colors: [
                    .clear,
                    .white.opacity(0.35),
                    .clear,
                ]),
                mode: .overlay(blendMode: .screen)
            )
            .clipShape(.rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(rowBorderColor, lineWidth: showsSelectionAccent ? 1.2 : 1)
            }
            .contentShape(.rect(cornerRadius: 12))
            .animation(.easeInOut(duration: 0.18), value: isSelected)
            .animation(.easeInOut(duration: 0.18), value: isWarming)
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.55)
        .contextMenu {
            contextMenuItems
        }
    }

    private var subtitle: String {
        if isWarming {
            return "Warming up selected model"
        }

        var parts = [option.descriptor.parameters]
        if let size = option.sizeLabel {
            parts.append(size)
        }
        return parts.joined(separator: " · ")
    }

    private var subtitleColor: Color {
        isWarming ? .orange : .secondary
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

        if shouldClipIcon {
            image.clipShape(.rect(cornerRadius: 6))
        } else {
            image
        }
    }

    private var shouldClipIcon: Bool {
        option.provider != .nvidia
    }

    private var showsSelectionAccent: Bool {
        isSelected || isWarming
    }

    private var rowAccentColor: Color {
        isWarming ? .orange : .accentColor
    }

    private var rowBackground: Color {
        if isWarming {
            return .orange.opacity(0.11)
        }
        if isSelected {
            return Color.accentColor.opacity(0.11)
        }
        return Color(nsColor: .controlBackgroundColor)
    }

    private var rowBorderColor: Color {
        if isWarming {
            return .orange.opacity(0.75)
        }
        if isSelected {
            return Color.accentColor.opacity(0.75)
        }
        return Color(nsColor: .separatorColor)
    }

    @ViewBuilder
    private var trailingAccessory: some View {
        switch downloadState {
        case .ready:
            if isWarming {
                warmingAccessory
            } else if isSelected {
                EmptyView()
            } else {
                pillAccessory(.use)
            }
        case .needsDownload:
            pillAccessory(.get)
        case .deleting:
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.6)
                .frame(width: 24, height: 24)
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
        case .deleting:
            return "Deleting download"
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
        case .needsDownload, .deleting, .preparing, .downloading, .paused:
            return .secondary
        case .failed:
            return .red
        }
    }

    private var showsStatusText: Bool {
        switch downloadState {
        case .ready, .needsDownload:
            return false
        case .deleting, .preparing, .downloading, .paused, .failed:
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
        case get
        case use

        var title: String {
            switch self {
            case .get:
                return "Get"
            case .use:
                return "Use"
            }
        }

        var foregroundColor: Color {
            switch self {
            case .get:
                return .white
            case .use:
                return .black
            }
        }

        var backgroundColor: Color {
            switch self {
            case .get:
                return .accentColor
            case .use:
                return .white
            }
        }

        var borderColor: Color {
            switch self {
            case .get:
                return .accentColor
            case .use:
                return Color(nsColor: .separatorColor)
            }
        }
    }

    private var warmingAccessory: some View {
        HStack(spacing: 6) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.orange)
                .scaleEffect(0.48)
                .frame(width: 12, height: 12)
            Text("Warming")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.orange)
        .frame(width: 82, height: 24)
        .background(.orange.opacity(0.14), in: .capsule)
        .overlay {
            Capsule()
                .strokeBorder(.orange.opacity(0.65), lineWidth: 1)
        }
    }

    private func pillAccessory(_ style: AccessoryPillStyle) -> some View {
        Text(style.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(style.foregroundColor)
            .lineLimit(1)
            .frame(width: 64, height: 24)
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
