import SwiftUI

/// The floating capsule in the liquid style: one dark glass drop, drawn by
/// `LiquidGlass.metal`, that carries the content of every phase.
struct LiquidCapsuleStage: View {
    private typealias Curve = LiquidCapsuleChoreography

    @Bindable var state: FloatingCapsuleState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var timeline = LiquidCapsuleTimeline()
    @State private var isSettled = true
    @State private var displayedPhase = FloatingCapsuleState.Phase.hidden
    @State private var contentSizes: [String: CGSize] = [:]
    @State private var interaction = LiquidRecordingInteraction.idle
    @State private var secondaryConfirmsDelete = false
    @State private var isPillHovered = false
    @State private var isSecondaryHovered = false

    var body: some View {
        ZStack(alignment: .bottom) {
            if state.showsLiveTranscript {
                LiveTranscriptCard(text: state.liveTranscript)
                    .padding(.bottom, Curve.bottomInset + Curve.pillHeight + 12)
                    .transition(.opacity)
            }

            TimelineView(.animation(paused: isSettled)) { context in
                let time = isSettled ? timeline.settledTime : context.date.timeIntervalSinceReferenceDate
                LiquidCapsuleScene(
                    frame: timeline.frame(at: time),
                    showsRipple: !reduceTransparency
                ) {
                    pillContent
                } secondary: {
                    secondaryButton
                }
                .allowsHitTesting(timeline.isPresented)
            }
            .frame(width: Curve.stageSize.width, height: Curve.stageSize.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(.smooth(duration: 0.3), value: state.showsLiveTranscript)
        .onChange(of: reduceMotion, initial: true) { _, reduceMotion in
            timeline.reduceMotion = reduceMotion
        }
        .onChange(of: state.phase, initial: true) { old, new in
            phaseChanged(from: old, to: new)
        }
        .onChange(of: interaction) { _, interaction in
            if interaction.showsSecondary {
                secondaryConfirmsDelete = interaction == .confirmingCancel
            }
            update { $0.setSplit(interaction.showsSecondary && displayedPhase == .recording, at: $1) }
        }
        .onChange(of: isPillHovered || isSecondaryHovered) { _, isHovering in
            guard displayedPhase == .recording else { return }
            if isHovering, interaction == .idle {
                interaction = .hovered
            }
        }
        .task(id: isPillHovered || isSecondaryHovered) {
            guard !(isPillHovered || isSecondaryHovered), interaction == .hovered else { return }
            // Crossing the gap between the pill and the stop drop must not collapse the split.
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, interaction == .hovered else { return }
            interaction = .idle
        }
        .task(id: interaction) {
            guard interaction == .confirmingCancel else { return }
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, interaction == .confirmingCancel else { return }
            interaction = isPillHovered || isSecondaryHovered ? .hovered : .idle
        }
        .task(id: timeline.settledTime) {
            let remaining = timeline.settledTime - Date.now.timeIntervalSinceReferenceDate
            if remaining > 0 {
                try? await Task.sleep(for: .seconds(remaining))
                guard !Task.isCancelled else { return }
            }
            isSettled = true
        }
    }

    // MARK: - Content

    private var pillContent: some View {
        ZStack {
            phaseView(displayedPhase)
                .fixedSize()
                .onGeometryChange(for: CGSize.self, of: \.size) { [id = displayedPhase.contentID] size in
                    contentSizes[id] = size
                    guard id == displayedPhase.contentID else { return }
                    update { $0.resize(to: size, at: $1) }
                }
                .id(displayedPhase.contentID)
                .transition(.blurReplace)
        }
        .environment(\.colorScheme, .dark)
        .onHover { isPillHovered = $0 }
    }

    @ViewBuilder
    private func phaseView(_ phase: FloatingCapsuleState.Phase) -> some View {
        if phase == .recording {
            LiquidRecordingPill(level: state.level, interaction: interaction) {
                guard interaction != .submitted else { return }
                interaction = .submitted
                state.onRecordingTapped?()
            }
        } else {
            FloatingCapsulePhaseContent(state: state, phase: phase, blur: 0)
        }
    }

    private var secondaryButton: some View {
        Button {
            if secondaryConfirmsDelete {
                interaction = .submitted
                state.onCancelRecordingTapped?()
            } else {
                interaction = .confirmingCancel
            }
        } label: {
            Image(systemName: secondaryConfirmsDelete ? "trash.fill" : "stop.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.red)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: Curve.secondarySize.width, height: Curve.secondarySize.height)
                .contentShape(Squircle())
        }
        .buttonStyle(.plain)
        .onHover { isSecondaryHovered = $0 }
        .help(secondaryConfirmsDelete ? "Delete recording" : "Cancel recording")
        .accessibilityLabel(secondaryConfirmsDelete ? "Confirm delete recording" : "Cancel recording")
    }

    // MARK: - Events

    private func phaseChanged(from old: FloatingCapsuleState.Phase, to new: FloatingCapsuleState.Phase) {
        let cue = LiquidCapsuleCue.transition(from: old, to: new)
        if new != .recording {
            interaction = .idle
        }
        switch cue {
        case .none:
            return
        case .present:
            displayedPhase = new
            let size = contentSizes[new.contentID] ?? LiquidCapsuleTimeline.defaultSize
            update { $0.present(size: size, glow: new.liquidGlow, at: $1) }
        case .resize, .pulse:
            withAnimation(.smooth(duration: 0.3)) {
                displayedPhase = new
            }
            update { timeline, now in
                timeline.setSplit(false, at: now)
                timeline.setGlow(new.liquidGlow, at: now)
                if let size = contentSizes[new.contentID] {
                    timeline.resize(to: size, at: now)
                }
                if cue == .pulse {
                    timeline.pulse(at: now)
                }
            }
        case .dismiss:
            update { $0.dismiss(at: $1) }
        }
    }

    private func update(_ change: (inout LiquidCapsuleTimeline, Double) -> Void) {
        var next = timeline
        change(&next, Date.now.timeIntervalSinceReferenceDate)
        guard next != timeline else { return }
        timeline = next
        isSettled = false
    }
}

/// Places the glass and the content of one frame on the stage.
struct LiquidCapsuleScene<Pill: View, Secondary: View>: View {
    let frame: LiquidCapsuleFrame
    var showsRipple = true
    @ViewBuilder let pill: Pill
    @ViewBuilder let secondary: Secondary

    var body: some View {
        ZStack(alignment: .topLeading) {
            if frame.isVisible {
                LiquidGlassLayer(frame: frame, size: LiquidCapsuleChoreography.stageSize, showsRipple: showsRipple)

                pill
                    .modifier(LiquidGlassContent(blob: frame.pill, opacity: frame.contentOpacity, blur: frame.contentBlur))

                if frame.secondary.size.width > 0 {
                    secondary
                        .modifier(LiquidGlassContent(
                            blob: frame.secondary,
                            opacity: frame.secondaryOpacity,
                            blur: frame.secondaryBlur
                        ))
                        .allowsHitTesting(frame.isSplit)
                        .accessibilityHidden(!frame.isSplit)
                }
            }
        }
        .frame(
            width: LiquidCapsuleChoreography.stageSize.width,
            height: LiquidCapsuleChoreography.stageSize.height,
            alignment: .topLeading
        )
    }
}

/// Centers content on a glass blob and clips it to the blob's current squircle.
private struct LiquidGlassContent: ViewModifier {
    var blob: LiquidCapsuleFrame.Blob
    var opacity: Double
    var blur: Double

    func body(content: Content) -> some View {
        content
            .frame(width: max(blob.size.width, 0), height: max(blob.size.height, 0))
            .clipShape(Squircle())
            .contentShape(Squircle())
            .blur(radius: blur)
            .opacity(opacity)
            .position(blob.center)
    }
}
