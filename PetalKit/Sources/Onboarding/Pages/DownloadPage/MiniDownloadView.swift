import ModelDownloadFeature
import Shared
import SwiftUI
import UI

public struct MiniDownloadView: View {
    @Bindable var model: ModelDownloadModel
    var onExpand: () -> Void
    @State private var isHovered = false
    private let contentVerticalOffset: CGFloat = -8

    public init(model: ModelDownloadModel, onExpand: @escaping () -> Void) {
        self.model = model
        self.onExpand = onExpand
    }
 
    public var body: some View {
        progressContent
            .frame(width: 130, height: 110)
            .offset(y: contentVerticalOffset)
            .overlay {
                expandButton
                    .offset(y: contentVerticalOffset)
            }
            .animation(.easeInOut(duration: 0.2), value: isHovered)
            .onHover { isHovered = $0 }
    }

    private var progressContent: some View {
        VStack {
            ZStack {
                if let icon = model.selectedModelOption?.provider.icon {
                    icon
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .opacity(0.5)
                        .blur(radius: 24)
                        .brightness(-0.3)
                        .ignoresSafeArea()
                }

                CircularProgressRing(
                    progress: progressFraction,
                    size: 84,
                    lineWidth: 6
                )

                VStack {
                    Text(percentText)
                        .font(.title.bold())
                        .contentTransition(.numericText(value: progressFraction))

                    if let speedText {
                        Text(speedText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var expandButton: some View {
        if isHovered {
            Button(action: onExpand) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .padding()
            }

            .buttonStyle(.plain)
            .background(.ultraThinMaterial, in: .circle)
            .contentShape(Circle())
            .help("Expand to full window")
            .transition(.opacity)
        }
    }

    private var progressFraction: Double {
        model.state.progress?.fraction ?? 0
    }

    private var percentText: String {
        let percent = Int((progressFraction * 100).rounded())
        return "\(percent)%"
    }

    private var speedText: String? {
        model.state.progress?.speedText
    }
}

@MainActor private func previewModel(state: ModelDownloadState) -> ModelDownloadModel {
    let model = ModelDownloadModel()
    model.state = state
    return model
}

#Preview("Downloading") {
    MiniDownloadView(
        model: previewModel(state: .downloading(.init(
            fraction: 0.42,
            statusText: "Downloading model...",
            speedText: "18.2 MB/s"
        ))),
        onExpand: {}
    )
}

#Preview("Downloading - Almost Done") {
    MiniDownloadView(
        model: previewModel(state: .downloading(.init(
            fraction: 0.93,
            statusText: "Downloading model...",
            speedText: "24.7 MB/s"
        ))),
        onExpand: {}
    )
}

#Preview("Paused") {
    MiniDownloadView(
        model: previewModel(state: .paused(.init(
            fraction: 0.42,
            statusText: "Download paused"
        ))),
        onExpand: {}
    )
}

#Preview("Just Started") {
    MiniDownloadView(
        model: previewModel(state: .downloading(.init(
            fraction: 0.02,
            statusText: "Downloading model...",
            speedText: "3.1 MB/s"
        ))),
        onExpand: {}
    )
}

#Preview("Not Downloaded") {
    MiniDownloadView(
        model: previewModel(state: .notDownloaded),
        onExpand: {}
    )
}
