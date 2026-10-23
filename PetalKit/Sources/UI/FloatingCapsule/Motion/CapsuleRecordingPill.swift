import SwiftUI

enum CapsuleRecordingInteraction: Hashable {
    case idle
    case hovered
    case confirmingCancel
    case submitted

    /// The stop button splits off the pill while the pointer is over the capsule.
    var showsSecondary: Bool {
        self == .hovered || self == .confirmingCancel
    }
}

/// The recording pill of the stage capsule. The stop button lives in the
/// secondary drop that splits off the pill, see ``CapsuleStage``.
struct CapsuleRecordingPill: View {
    let level: Double
    let interaction: CapsuleRecordingInteraction
    let transcribe: () -> Void

    @State private var isTranscribeHovering = false

    var body: some View {
        ZStack {
            LiveWaveform(
                level: level,
                bars: 37,
                rows: 7,
                tint: .red,
                metrics: .floatingRecording,
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
                transcribeButton
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            case .confirmingCancel:
                Text("Are you sure?")
                    .font(.callout.weight(.semibold))
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            case .submitted:
                ProgressView()
                    .controlSize(.small)
            }
        }
        .floatingCapsuleChrome(
            contentWidth: 174,
            contentHeight: 28,
            horizontalPadding: 4,
            verticalPadding: 7
        )
        .animation(.smooth(duration: 0.18), value: interaction)
    }

    private var transcribeButton: some View {
        Button(action: transcribe) {
            Text("Transcribe")
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.opacity(isTranscribeHovering ? 0.14 : 0.06), in: Squircle())
                .contentShape(Squircle())
        }
        .buttonStyle(.plain)
        .onHover { isTranscribeHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isTranscribeHovering)
        .help("Stop recording and transcribe")
        .accessibilityHint("Stops recording and starts transcription")
    }
}
