import Shared
import SwiftUI

public struct FloatingCapsuleView: View {
    @Bindable var state: FloatingCapsuleState
    @Shared(.floatingCapsuleBackgroundStyle) private var backgroundStyle
    // Pre-macOS 26 only: a blur pulse masks the swap between separate glass
    // surfaces. On macOS 26 the surfaces are one morphing Liquid Glass capsule,
    // so no pulse is needed and this stays at 0.
    @State private var blurRadius: CGFloat = 0
    @Namespace private var glassNamespace

    public init(state: FloatingCapsuleState) {
        self.state = state
    }

    public var body: some View {
        if backgroundStyle == .liquid {
            LiquidCapsuleStage(state: state)
        } else {
            classic
        }
    }

    private var classic: some View {
        VStack(spacing: 12) {
            if state.showsLiveTranscript {
                liveTranscript
            }
            capsule.fixedSize()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 4)
        .animation(.smooth(duration: 0.3), value: state.phase)
        .onChange(of: state.phase) { _, newPhase in
            guard newPhase != .hidden else { return }
            // Native Liquid Glass morphs the capsule between statuses, so
            // the manual blur pulse is only needed on the pre-26 fallback.
            if #unavailable(macOS 26.0) {
                blurRadius = 12
                withAnimation(.easeOut(duration: 0.5)) {
                    blurRadius = 0
                }
            }
        }
    }

    private var liveTranscript: some View {
        LiveTranscriptCard(text: state.liveTranscript)
    }

    /// On macOS 26 every status renders into a single `GlassEffectContainer`
    /// and shares one `glassEffectID`, so the capsule matched-geometry morphs
    /// its shape as the status changes. Older systems get the blur-masked swap.
    @ViewBuilder
    private var capsule: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 8) {
                phaseContent
                    .id(phaseID)
                    .transition(statusTransition)
            }
            .environment(\.glassCapsuleNamespace, glassNamespace)
        } else {
            phaseContent
                .id(phaseID)
                .transition(statusTransition)
                .blur(radius: blurRadius > 0 ? 8 : 0)
        }
    }

    private var statusTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.94)),
            removal: .opacity.combined(with: .scale(scale: 1.03))
        )
    }

    private var phaseID: String { state.phase.contentID }

    private var phaseContent: some View {
        FloatingCapsulePhaseContent(state: state, phase: state.phase, blur: blurRadius)
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
