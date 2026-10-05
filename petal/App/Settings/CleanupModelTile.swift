import Shared
import SwiftUI

struct CleanupModelTile: View {
    let model: CleanupModel
    let isSelected: Bool
    var isAvailable = true
    /// `nil` when the model needs no download.
    var downloadState: ModelDownloadState?
    var sizeLabel: String?
    var detail: String?
    var needsSetup = false
    var onCancelDownload: (() -> Void)?
    var onDeleteDownload: (() -> Void)?
    let action: () -> Void

    var body: some View {
        SelectableCard(isSelected: isSelected, action: action) {
            VStack(spacing: 7) {
                CleanupModelIcon(model: model, size: 32)
                    .overlay(alignment: .topTrailing) {
                        if case let .downloading(progress)? = downloadState {
                            CircularDownloadProgress(fraction: progress.fraction)
                                .background(.background, in: .circle)
                                .offset(x: 8, y: -6)
                        }
                    }

                VStack(spacing: 2) {
                    Text(model.displayName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(status ?? " ")
                        .font(.caption2)
                        .foregroundStyle(isFailed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1 : 0.5)
        .contextMenu { contextMenuItems }
        .animation(.easeInOut(duration: 0.18), value: isSelected)
        .help(model.summary ?? "Paste your words as you said them.")
        .accessibilityLabel(model.displayName)
        .accessibilityValue(status ?? "")
    }

    private var isFailed: Bool {
        downloadState?.is(\.failed) == true
    }

    private var status: String? {
        guard isAvailable else { return "Unavailable" }
        switch downloadState {
        case nil:
            if needsSetup { return "Set Up" }
            return detail
        case .downloaded?:
            return nil
        case .notDownloaded?:
            return ["Get", sizeLabel].compactMap(\.self).joined(separator: " · ")
        case .preparing?:
            return "Preparing…"
        case let .downloading(progress)?:
            return "\(Int((progress.fraction * 100).rounded()))%"
        case .paused?:
            return "Paused"
        case .failed?:
            return "Try Again"
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
    VStack(spacing: 16) {
        HStack(spacing: 8) {
            CleanupModelTile(model: .off, isSelected: false) {}
            CleanupModelTile(model: .appleIntelligence, isSelected: true) {}
            CleanupModelTile(model: .petalW1, isSelected: false, downloadState: .notDownloaded, sizeLabel: "1.0 GB") {}
            CleanupModelTile(model: .cloud, isSelected: false, needsSetup: true) {}
        }
        HStack(spacing: 8) {
            CleanupModelTile(model: .off, isSelected: false) {}
            CleanupModelTile(model: .appleIntelligence, isSelected: false, isAvailable: false) {}
            CleanupModelTile(model: .petalW1, isSelected: true, downloadState: .downloading(.init(fraction: 0.42, statusText: ""))) {}
            CleanupModelTile(model: .cloud, isSelected: false, detail: "gpt-6-luna") {}
        }
    }
    .frame(width: 440)
    .padding()
}
