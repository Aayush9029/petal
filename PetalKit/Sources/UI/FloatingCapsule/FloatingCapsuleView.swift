import Shared
import SwiftUI

public struct FloatingCapsuleView: View {
    @Bindable var state: FloatingCapsuleState
    @Shared(.floatingCapsuleBackgroundStyle) private var backgroundStyle
    @State private var blurRadius: CGFloat = 0

    public init(state: FloatingCapsuleState) {
        self.state = state
    }

    public var body: some View {
        if let material = CapsuleStage.Material(style: backgroundStyle) {
            CapsuleStage(state: state, material: material)
        } else {
            visualEffectFallback
        }
    }

    /// Glass before macOS 26: separate translucent surfaces, with a blur pulse
    /// that masks the swap between statuses.
    private var visualEffectFallback: some View {
        VStack(spacing: 12) {
            if state.showsLiveTranscript {
                LiveTranscriptCard(text: state.liveTranscript)
            }
            FloatingCapsulePhaseContent(state: state, phase: state.phase, blur: blurRadius)
                .id(state.phase.contentID)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.94)),
                    removal: .opacity.combined(with: .scale(scale: 1.03))
                ))
                .blur(radius: blurRadius > 0 ? 8 : 0)
                .fixedSize()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 4)
        .animation(.smooth(duration: 0.3), value: state.phase)
        .onChange(of: state.phase) { _, newPhase in
            guard newPhase != .hidden else { return }
            blurRadius = 12
            withAnimation(.easeOut(duration: 0.5)) {
                blurRadius = 0
            }
        }
    }
}

// MARK: - Preview

#Preview("Floating Capsule") {
    FloatingCapsulePreview()
}

private struct FloatingCapsulePreview: View {
    @State private var state = FloatingCapsuleState()
    @State private var phaseIndex = 1

    private let phases: [(String, FloatingCapsuleState.Phase)] = [
        ("Hidden", .hidden),
        ("Recording", .recording),
        ("Confirm Cancel", .confirmCancel),
        ("Trimming", .trimming),
        ("Speeding", .speeding),
        ("Transcribing", .transcribing),
        ("Refining", .refining),
        ("Copied", .copiedToClipboard),
        ("Accessibility", .accessibilityPrompt),
        ("AX Enabled", .accessibilityEnabled),
        ("Error", .error("Preview")),
    ]

    var body: some View {
        VStack(spacing: 20) {
            FloatingCapsuleView(state: state)
                .frame(width: 400, height: 60)
                .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))

            HStack(spacing: 16) {
                Button(action: prev) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)

                Text(phases[phaseIndex].0)
                    .font(.footnote.weight(.medium))
                    .frame(width: 120)

                Button(action: next) {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(24)
        .onAppear { applyPhase() }
    }

    private func prev() {
        phaseIndex = (phaseIndex - 1 + phases.count) % phases.count
        applyPhase()
    }

    private func next() {
        phaseIndex = (phaseIndex + 1) % phases.count
        applyPhase()
    }

    private func applyPhase() {
        state.phase = phases[phaseIndex].1
        state.level = 0.72
        state.transcriptionProgress = 0.64
    }
}
