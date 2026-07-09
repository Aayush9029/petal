import SwiftUI

struct RecordingCapsuleButton: View {
    let level: Double
    let blur: CGFloat
    let transcribe: () -> Void

    @State private var interaction = Interaction.idle

    var body: some View {
        Button(action: transcribeButtonTapped) {
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
                .opacity(interaction == .idle ? 1 : 0.28)

                Text("Transcribe")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .opacity(interaction == .idle ? 0 : 1)
            }
            .floatingCapsuleChrome(blur: blur)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(interaction == .submitted)
        .animation(.smooth(duration: 0.18), value: interaction)
        .onHover { isHovering in
            guard interaction != .submitted else { return }
            interaction = isHovering ? .hovered : .idle
        }
        .help("Stop recording and transcribe")
        .accessibilityLabel("Transcribe")
        .accessibilityHint("Stops recording and starts transcription")
    }

    private func transcribeButtonTapped() {
        guard interaction != .submitted else { return }
        interaction = .submitted
        transcribe()
    }

    private enum Interaction {
        case idle
        case hovered
        case submitted
    }
}
