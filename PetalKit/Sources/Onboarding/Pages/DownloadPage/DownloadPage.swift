import AppKit
import ModelDownloadFeature
import Shared
import SwiftUI
import UI

struct DownloadPage: View {
    @Bindable var model: OnboardingModel
    @State private var isAnimating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
                .slideIn(active: isAnimating, delay: 0.25)

            if let option = downloadModel.selectedModelOption {
                downloadCard(option)
                    .slideIn(active: isAnimating, delay: 0.4)
            }

            errorText

            Spacer()
        }
        .onAppear { isAnimating = true }
    }

    private var header: some View {
        HStack {
            OnboardingHeader(
                symbol: selectedModelRequiresDownload ? "arrow.down.circle" : "checkmark.circle",
                title: selectedModelRequiresDownload ? "Download Model" : "Model Ready",
                description: selectedModelRequiresDownload
                    ? "This may take a few minutes depending on your connection."
                    : "This model uses Apple's built-in Speech framework and is ready instantly.",
                layout: .vertical
            )

            Spacer()
        }
        .overlay(alignment: .topTrailing) {
            if downloadModel.state.isActive || downloadModel.state.isPaused {
                Button {
                    model.minimizeToMiniWindow()
                } label: {
                    Image(systemName: "rectangle.inset.topright.filled")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Minimize to mini window")
            }
        }
    }

    @ViewBuilder
    private func downloadCard(_ option: ModelOption) -> some View {
        let icon = option.provider.icon
        let name = option.displayName
        let size = option.sizeLabel

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                icon
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(name)
                    .font(.headline)

                Spacer()

                trailingBadge(size: size)
            }

            switch downloadModel.state {
            case .notDownloaded:
                Text("Tap **Download Model** below to get started.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .failed:
                Text("Download failed. Tap **Download Model** to retry.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .preparing:
                ProgressView()
                    .controlSize(.small)

            case let .downloading(progress):
                downloadProgress(progress: progress.fraction, speedText: progress.speedText, isPaused: false)

            case let .paused(progress):
                downloadProgress(progress: progress.fraction, speedText: progress.speedText, isPaused: true)

            case .downloaded:
                if let url = downloadModel.modelDirectoryURL {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        Label("Show in Finder", systemImage: "folder")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.black))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        }
        .if(downloadModel.state.isActive) { view in
            view.runningBorder(
                radius: 16,
                lineWidth: 1,
                animated: true,
                duration: 1.5,
                colors: [.white.opacity(0.0), .white.opacity(0.7), .white.opacity(0.0)]
            )
        }
    }

    private func downloadProgress(progress: Double, speedText: String?, isPaused: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.title3.weight(.bold).monospacedDigit())
                    .intelligenceGradient()

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        if isPaused {
                            Task { await downloadModel.resumeButtonTapped() }
                        } else {
                            downloadModel.pauseButtonTapped()
                        }
                    } label: {
                        Image(systemName: isPaused ? "play.circle.fill" : "pause.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)

                    Button { downloadModel.cancelButtonTapped() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            ZStack(alignment: .top) {
                AnimatedIntelligenceBar(progress: progress)
                    .frame(height: 8)
                    .blur(radius: 10)
                    .opacity(isPaused ? 0.15 : 0.4)
                    .offset(y: 4)

                AnimatedIntelligenceBar(progress: progress)
                    .frame(height: 8)
            }

            HStack {
                if isPaused {
                    Text("Paused")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let speedText {
                    Text(speedText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func trailingBadge(size: String?) -> some View {
        switch downloadModel.state {
        case .downloaded:
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
        default:
            if let size {
                Text(size)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var errorText: some View {
        if let error = downloadModel.lastError ?? model.lastError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private var downloadModel: ModelDownloadModel {
        model.modelDownloadViewModel
    }

    private var selectedModelRequiresDownload: Bool {
        downloadModel.selectedModelOption?.requiresDownload ?? true
    }
}

private extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

#Preview("Download - Not Downloaded") {
    OnboardingView(model: .makePreview(page: .download))
}

#Preview("Download - In Progress") {
    OnboardingView(model: .makePreview(page: .download) { model in
        model.modelDownloadViewModel.state = .downloading(.init(
            fraction: 0.42,
            statusText: "Downloading model...",
            speedText: "18.2 MB/s"
        ))
    })
}

#Preview("Download - Paused") {
    OnboardingView(model: .makePreview(page: .download) { model in
        model.modelDownloadViewModel.state = .paused(.init(
            fraction: 0.42,
            statusText: "Download paused"
        ))
    })
}

#Preview("Download - Complete") {
    OnboardingView(model: .makePreview(page: .download) { model in
        model.modelDownloadViewModel.state = .downloaded
    })
}
