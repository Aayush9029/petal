import Assets
import Shared
import SwiftUI

struct CleanupModelCard: View {
    let model: CleanupModel
    let isSelected: Bool
    /// `nil` when the model needs no download.
    var downloadState: ModelDownloadState?
    var sizeLabel: String?
    var onCancelDownload: (() -> Void)?
    var onDeleteDownload: (() -> Void)?
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                icon
                    .frame(width: 28, height: 28)
                    .clipShape(.rect(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 3) {
                    Text(model.displayName)
                        .font(.subheadline.weight(.semibold))
                    if let summary = model.summary {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let metadata {
                        Text(metadata)
                            .font(.caption2)
                            .foregroundStyle(downloadState?.is(\.failed) == true ? AnyShapeStyle(.red) : AnyShapeStyle(.tertiary))
                    }
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
        .contextMenu { contextMenuItems }
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.18), value: isSelected)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var metadata: String? {
        switch downloadState {
        case nil, .downloaded?:
            nil
        case .notDownloaded?:
            ["Download required", sizeLabel].compactMap(\.self).joined(separator: " · ")
        case .preparing?:
            "Preparing download…"
        case let .downloading(progress)?, let .paused(progress)?:
            "Downloading · \(progress.summaryText)"
        case let .failed(message)?:
            message
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch model {
        case .off:
            Image(systemName: "text.alignleft")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.gray.gradient)
        case .appleIntelligence:
            Image.appleIntelligence
                .resizable()
                .aspectRatio(contentMode: .fill)
        case .s1Mini:
            Image.superwhisper
                .resizable()
                .aspectRatio(contentMode: .fill)
        }
    }

    @ViewBuilder
    private var selectionBackground: some View {
        if isSelected {
            Color.accentColor.opacity(0.09)
        } else if isHovering {
            Color.primary.opacity(0.045)
        }
    }

    @ViewBuilder
    private var trailingAccessory: some View {
        switch downloadState {
        case .preparing?:
            ProgressView()
                .controlSize(.small)
        case let .downloading(progress)?:
            CircularDownloadProgress(fraction: progress.fraction)
        case .notDownloaded?, .failed?:
            if !isSelected {
                Text("Get")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 24)
                    .background(Color.accentColor, in: .capsule)
            }
        case nil, .downloaded?, .paused?:
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
        }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        switch downloadState {
        case .downloaded?:
            if let onDeleteDownload {
                Button("Delete Download…", systemImage: "trash", role: .destructive, action: onDeleteDownload)
            }
        case .preparing?, .downloading?:
            if let onCancelDownload {
                Button("Cancel Download", systemImage: "xmark.circle", role: .destructive, action: onCancelDownload)
            }
        default:
            EmptyView()
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        CleanupModelCard(model: .off, isSelected: false) {}
        CleanupModelCard(model: .appleIntelligence, isSelected: true) {}
        CleanupModelCard(model: .s1Mini, isSelected: false, downloadState: .notDownloaded, sizeLabel: "619 MB") {}
        CleanupModelCard(model: .s1Mini, isSelected: true, downloadState: .downloading(.init(fraction: 0.42, statusText: "")), sizeLabel: "619 MB") {}
        CleanupModelCard(model: .s1Mini, isSelected: true, downloadState: .downloaded, sizeLabel: "619 MB") {}
    }
    .frame(width: 500)
}
