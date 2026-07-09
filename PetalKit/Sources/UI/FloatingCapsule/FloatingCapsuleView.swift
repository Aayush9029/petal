import SwiftUI

public struct FloatingCapsuleView: View {
    @Bindable var state: FloatingCapsuleState
    // Pre-macOS 26 only: a blur pulse masks the swap between separate glass
    // surfaces. On macOS 26 the surfaces are one morphing Liquid Glass capsule,
    // so no pulse is needed and this stays at 0.
    @State private var blurRadius: CGFloat = 0
    @Namespace private var glassNamespace

    public init(state: FloatingCapsuleState) {
        self.state = state
    }

    public var body: some View {
        capsule
            .fixedSize()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private var phaseID: String {
        switch state.phase {
        case .hidden: "hidden"
        case .recording: "recording"
        case .confirmCancel: "confirmCancel"
        case .trimming: "trimming"
        case .speeding: "speeding"
        case .transcribing: "transcribing"
        case .refining: "refining"
        case .copiedToClipboard: "copied"
        case .accessibilityPrompt: "accessibilityPrompt"
        case .accessibilityEnabled: "accessibilityEnabled"
        case .error: "error"
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch state.phase {
        case .hidden:
            Color.clear
        case .recording:
            recording
        case .confirmCancel:
            confirmCancel
        case .trimming, .speeding, .transcribing:
            processing
        case .refining:
            intelligenceProcessing
        case .copiedToClipboard:
            copiedToClipboard
        case .accessibilityPrompt:
            accessibilityPrompt
        case .accessibilityEnabled:
            accessibilityEnabled
        case .error:
            error
        }
    }

    // MARK: - Phase content

    private var recording: some View {
        RecordingCapsuleButton(
            level: state.level,
            blur: blurRadius,
            transcribe: { state.onRecordingTapped?() },
            cancel: { state.onCancelRecordingTapped?() }
        )
    }

    private var confirmCancel: some View {
        CancelConfirmationCapsule(isActive: state.cancelCountdownActive)
    }

    private var processing: some View {
        ProcessingWaveform(bars: 37, rows: 7, tint: .primary, metrics: .floating)
            .floatingCapsuleChrome(blur: blurRadius)
    }

    private var intelligenceProcessing: some View {
        IntelligenceProcessingWaveform(bars: 37, rows: 7, metrics: .floating)
            .shadow(color: .purple.opacity(0.35), radius: 5)
            .floatingCapsuleChrome(blur: blurRadius)
    }

    private var error: some View {
        HStack(spacing: 8) {
            DottedStatusGlyph(kind: .warning, tint: .orange)

            Text("Error")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .floatingCapsuleChrome(blur: blurRadius)
    }

    private var copiedToClipboard: some View {
        CopiedToClipboardCapsule(blur: blurRadius)
    }

    private var accessibilityPrompt: some View {
        AccessibilityCapsuleButton(blur: blurRadius) {
            state.onAccessibilityTapped?()
        }
    }

    private var accessibilityEnabled: some View {
        HStack(spacing: 8) {
            DottedStatusGlyph(kind: .checkmark, tint: .green)

            Text("Accessibility Enabled")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .floatingCapsuleChrome(blur: blurRadius)
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
