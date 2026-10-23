import SwiftUI

/// The content of one capsule phase, shared by every capsule style.
struct FloatingCapsulePhaseContent: View {
    @Bindable var state: FloatingCapsuleState
    let phase: FloatingCapsuleState.Phase
    let blur: CGFloat

    @ViewBuilder
    var body: some View {
        switch phase {
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
            blur: blur,
            transcribe: { state.onRecordingTapped?() },
            cancel: { state.onCancelRecordingTapped?() }
        )
    }

    private var confirmCancel: some View {
        CancelConfirmationCapsule(isActive: state.cancelCountdownActive)
    }

    private var processing: some View {
        ProcessingWaveform(bars: 37, rows: 7, tint: .primary, metrics: .floating)
            .floatingCapsuleChrome(blur: blur)
    }

    private var intelligenceProcessing: some View {
        IntelligenceProcessingWaveform(bars: 37, rows: 7, metrics: .floating)
            .shadow(color: .purple.opacity(0.35), radius: 5)
            .floatingCapsuleChrome(blur: blur)
    }

    private var error: some View {
        HStack(spacing: 8) {
            DottedStatusGlyph(kind: .warning, tint: .orange)

            Text("Error")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .floatingCapsuleChrome(blur: blur)
    }

    private var copiedToClipboard: some View {
        CopiedToClipboardCapsule(blur: blur)
    }

    private var accessibilityPrompt: some View {
        AccessibilityCapsuleButton(blur: blur) {
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
        .floatingCapsuleChrome(blur: blur)
    }
}
