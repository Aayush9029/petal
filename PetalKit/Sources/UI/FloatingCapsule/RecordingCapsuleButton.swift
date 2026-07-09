import SwiftUI

struct RecordingCapsuleButton: View {
    let level: Double
    let blur: CGFloat
    let transcribe: () -> Void
    let cancel: () -> Void

    @State private var interaction = Interaction.idle
    @State private var isHovering = false

    var body: some View {
        ZStack {
            LiveWaveform(
                level: level,
                bars: 37,
                rows: 7,
                tint: .red,
                metrics: .floating,
                gain: 0.82,
                responseExponent: 1.35,
                sampleInterval: .milliseconds(36)
            )
            .blur(radius: interaction == .idle ? 0 : 2)
            .opacity(interaction == .idle ? 1 : 0.18)

            switch interaction {
            case .idle:
                EmptyView()
            case .hovered:
                actionRow
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            case .confirmingCancel:
                confirmationRow
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            case .submitted:
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(width: 174, height: 24)
        .floatingCapsuleChrome(
            blur: blur,
            contentWidth: 174,
            horizontalPadding: 4
        )
        .contentShape(Capsule())
        .animation(.smooth(duration: 0.18), value: interaction)
        .onHover { isHovering in
            self.isHovering = isHovering
            guard interaction == .idle || interaction == .hovered else { return }
            interaction = isHovering ? .hovered : .idle
        }
        .task(id: interaction) {
            guard interaction == .confirmingCancel else { return }
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, interaction == .confirmingCancel else { return }
            interaction = isHovering ? .hovered : .idle
        }
        .accessibilityElement(children: .contain)
    }

    private var actionRow: some View {
        HStack(spacing: 6) {
            Button(action: transcribeButtonTapped) {
                Text("Transcribe")
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.primary.opacity(0.1), in: .capsule)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .help("Stop recording and transcribe")
            .accessibilityHint("Stops recording and starts transcription")

            Button(action: requestCancel) {
                Image(systemName: "stop.fill")
                    .font(.caption.weight(.bold))
                    .frame(width: 30, height: 24)
                    .background(Color.red.opacity(0.16), in: .capsule)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .help("Cancel recording")
        }
    }

    private var confirmationRow: some View {
        HStack(spacing: 6) {
            Text("Are you sure?")
                .font(.callout.weight(.semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.red.opacity(0.1), in: .capsule)

            Button(action: confirmCancel) {
                Image(systemName: "trash.fill")
                    .font(.caption.weight(.bold))
                    .frame(width: 30, height: 24)
                    .background(Color.red.opacity(0.2), in: .capsule)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .help("Delete recording")
            .accessibilityLabel("Confirm delete recording")
        }
    }

    private func transcribeButtonTapped() {
        guard interaction != .submitted else { return }
        interaction = .submitted
        transcribe()
    }

    private func requestCancel() {
        interaction = .confirmingCancel
    }

    private func confirmCancel() {
        interaction = .submitted
        cancel()
    }

    private enum Interaction: Hashable {
        case idle
        case hovered
        case confirmingCancel
        case submitted
    }
}
