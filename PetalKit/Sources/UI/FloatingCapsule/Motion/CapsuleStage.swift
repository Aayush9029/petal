import Shared
import SwiftUI

struct CapsuleStage: View {
    private typealias Curve = CapsuleChoreography

    enum Material: Equatable {
        case future
        case systemGlass

        init?(style: FloatingCapsuleBackgroundStyle) {
            switch style {
            case .future:
                self = .future
            case .liquidGlass:
                guard #available(macOS 26.0, *) else { return nil }
                self = .systemGlass
            }
        }
    }

    @Bindable var state: FloatingCapsuleState
    let material: Material
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    @State private var motion = CapsuleMotion()
    @State private var displayedPhase = FloatingCapsuleState.Phase.hidden
    @State private var contentSizes: [String: CGSize] = [:]
    @State private var interaction = CapsuleRecordingInteraction.idle
    @State private var secondaryConfirmsDelete = false
    @State private var isPillHovered = false
    @State private var isSecondaryHovered = false
    @State private var discardsRecording = false
    @State private var stageOrigin = CGPoint.zero

    var body: some View {
        ZStack(alignment: .bottom) {
            if state.showsLiveTranscript {
                LiveTranscriptCard(text: state.liveTranscript)
                    .padding(.bottom, Curve.bottomInset + Curve.pillHeight + 12)
                    .transition(.opacity)
            }

            TimelineView(.animation(
                minimumInterval: isSettled && !timeline.isOrbiting ? 1.0 / 30.0 : nil,
                paused: isSettled && (reduceMotion || !timeline.isPresented)
            )) { context in
                let now = context.date.timeIntervalSinceReferenceDate
                CapsuleScene(
                    frame: timeline.frame(at: isSettled ? timeline.settledTime : now),
                    material: material,
                    showsRipple: !reduceTransparency,
                    light: light(at: now)
                ) {
                    pillContent
                } secondary: {
                    secondaryButton
                }
                .allowsHitTesting(timeline.isPresented)
            }
            .frame(width: Curve.stageSize.width, height: Curve.stageSize.height)
            .onGeometryChange(for: CGPoint.self, of: { $0.frame(in: .global).origin }) { stageOrigin = $0 }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(.smooth(duration: 0.3), value: state.showsLiveTranscript)
        .onChange(of: hitRegion, initial: true) { _, region in
            state.hitRegion = region
        }
        .onChange(of: reduceMotion, initial: true) { _, reduceMotion in
            motion.timeline.reduceMotion = reduceMotion
        }
        .onChange(of: state.level) { _, level in
            motion.level.retarget(level, at: Date.now.timeIntervalSinceReferenceDate)
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
        .onChange(of: confirmsDelete) { _, confirmsDelete in
            update { timeline, now in
                timeline.setDanger(confirmsDelete, at: now)
                timeline.setGlow(confirmsDelete ? Self.deleteGlow : displayedPhase.capsuleGlow, at: now)
            }
        }
        .onChange(of: hoverTargets) { _, targets in
            update { $0.setHover(stop: targets.stop, transcribe: targets.transcribe, at: $1) }
        }
        .onChange(of: isPillHovered || isSecondaryHovered) { _, isHovering in
            guard displayedPhase == .recording else { return }
            if isHovering, interaction == .idle {
                interaction = .hovered
            }
        }
        .task(id: isPillHovered || isSecondaryHovered) {
            guard !(isPillHovered || isSecondaryHovered), interaction == .hovered else { return }
            // Keep the split open while the pointer crosses the gap.
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, interaction == .hovered else { return }
            interaction = .idle
        }
        .task(id: interaction) {
            guard interaction == .confirmingCancel else { return }
            try? await Task.sleep(for: FloatingCapsuleState.cancelConfirmationTimeout)
            guard !Task.isCancelled, interaction == .confirmingCancel else { return }
            interaction = isPillHovered || isSecondaryHovered ? .hovered : .idle
        }
        .task(id: timeline.settledTime) {
            let remaining = timeline.settledTime - Date.now.timeIntervalSinceReferenceDate
            if remaining > 0 {
                try? await Task.sleep(for: .seconds(remaining))
                guard !Task.isCancelled else { return }
            }
            motion.isSettled = true
            // The dismissal keeps the last phase mounted after the panel hides.
            if !timeline.isPresented {
                displayedPhase = .hidden
            }
        }
    }

    private var timeline: CapsuleTimeline { motion.timeline }

    private var hitRegion: CGRect? {
        guard timeline.isPresented else { return nil }
        let frame = timeline.frame(at: timeline.settledTime)
        var region = frame.pill.rect
        if frame.secondary.size.width > 0 {
            region = region.union(frame.secondary.rect)
        }
        return region.insetBy(dx: -8, dy: -8).offsetBy(dx: stageOrigin.x, dy: stageOrigin.y)
    }
    private var isSettled: Bool { motion.isSettled }

    private struct HoverTargets: Equatable {
        var stop: Bool
        var transcribe: Bool
    }

    private var hoverTargets: HoverTargets {
        let isRecording = displayedPhase == .recording
        return HoverTargets(
            stop: isRecording && isSecondaryHovered && interaction.showsSecondary,
            transcribe: isRecording && isPillHovered && interaction == .hovered
        )
    }

    private static let deleteGlow: SIMD3<Double> = [0.36, 0.06, 0.08]

    private var confirmsDelete: Bool {
        displayedPhase == .confirmCancel || interaction == .confirmingCancel
            || (interaction == .submitted && discardsRecording)
    }

    private var highlightStrength: Double {
        switch material {
        case .future: colorScheme == .dark ? 0.5 : 0.7
        case .systemGlass: 0.2
        }
    }

    private func light(at now: Double) -> CapsuleLight {
        let orbit = timeline.orbit(at: now)
        let level = displayedPhase == .recording && timeline.isPresented ? motion.level.value(at: now) : 0
        return CapsuleLight(
            time: reduceMotion ? 0 : now - (timeline.presentedAt ?? now),
            level: reduceMotion ? 0 : level,
            strength: highlightStrength,
            orbitTurns: reduceMotion ? 0 : orbit.turns,
            orbitStrength: orbit.strength,
            orbitIsStill: reduceMotion
        )
    }

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
        .environment(\.capsuleStageDrawsGlass, true)
        .modifier(DarkContentOnFutureGlass(material: material))
        .onHover { isPillHovered = $0 }
    }

    @ViewBuilder
    private func phaseView(_ phase: FloatingCapsuleState.Phase) -> some View {
        if phase == .recording {
            CapsuleRecordingPill(level: state.level, interaction: interaction) {
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
                discardsRecording = true
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

    private func phaseChanged(from old: FloatingCapsuleState.Phase, to new: FloatingCapsuleState.Phase) {
        let cue = CapsuleCue.transition(from: old, to: new, isPresented: timeline.isPresented)
        let discards = discardsRecording || (old == .confirmCancel && new == .hidden)
        if new != .recording {
            interaction = .idle
        }
        switch cue {
        case .none:
            return
        case .present:
            discardsRecording = false
            displayedPhase = new
            let size = contentSizes[new.contentID] ?? CapsuleTimeline.defaultSize
            update { timeline, now in
                timeline.present(size: size, glow: new.capsuleGlow, at: now)
                timeline.setOrbit(new.isProcessing, at: now)
            }
        case .resize, .pulse:
            withAnimation(.smooth(duration: 0.3)) {
                displayedPhase = new
            }
            update { timeline, now in
                timeline.setSplit(false, at: now)
                timeline.setGlow(new.capsuleGlow, at: now)
                if let size = contentSizes[new.contentID] {
                    timeline.resize(to: size, at: now)
                }
                if cue == .pulse {
                    timeline.pulse(at: now)
                }
                timeline.setOrbit(new.isProcessing, at: now)
            }
        case .dismiss:
            discardsRecording = false
            update { $0.dismiss(at: $1, style: discards ? .burst : .shrink) }
        }
    }

    private func update(_ change: (inout CapsuleTimeline, Double) -> Void) {
        let before = motion.timeline
        change(&motion.timeline, Date.now.timeIntervalSinceReferenceDate)
        guard motion.timeline != before else { return }
        motion.isSettled = false
    }
}

private struct DarkContentOnFutureGlass: ViewModifier {
    let material: CapsuleStage.Material

    func body(content: Content) -> some View {
        if material == .future {
            content.environment(\.colorScheme, .dark)
        } else {
            content
        }
    }
}

struct CapsuleScene<Pill: View, Secondary: View>: View {
    let frame: CapsuleFrame
    var material = CapsuleStage.Material.future
    var showsRipple = true
    var light = CapsuleLight()
    @ViewBuilder let pill: Pill
    @ViewBuilder let secondary: Secondary

    var body: some View {
        ZStack(alignment: .topLeading) {
            if frame.isVisible {
                glass

                pill
                    .modifier(CapsuleBlobContent(blob: frame.pill, opacity: frame.contentOpacity, blur: frame.contentBlur))

                if frame.secondary.size.width > 0 {
                    secondary
                        .modifier(CapsuleBlobContent(
                            blob: frame.secondary,
                            opacity: frame.secondaryOpacity,
                            blur: frame.secondaryBlur
                        ))
                        .allowsHitTesting(frame.isSplit)
                        .accessibilityHidden(!frame.isSplit)
                }
            }
        }
        .blur(radius: frame.glassBlur)
        .frame(
            width: CapsuleChoreography.stageSize.width,
            height: CapsuleChoreography.stageSize.height,
            alignment: .topLeading
        )
    }
}

extension CapsuleScene {
    @ViewBuilder
    private var glass: some View {
        let size = CapsuleChoreography.stageSize
        if material == .systemGlass, #available(macOS 26.0, *) {
            FutureGlassLayer(frame: frame.rippleOnly, size: size, showsRipple: showsRipple, clearDroplets: true)
            SystemGlassLayer(frame: frame, size: size, light: light)
        } else {
            FutureGlassLayer(frame: frame, size: size, showsRipple: showsRipple, light: light)
        }
    }
}

private struct CapsuleBlobContent: ViewModifier {
    var blob: CapsuleFrame.Blob
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
