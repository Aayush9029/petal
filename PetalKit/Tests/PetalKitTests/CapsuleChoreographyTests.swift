import CoreGraphics
import Shared
import Testing
@testable import UI

@Suite struct CapsuleChoreographyTests {
    private typealias Curve = CapsuleChoreography
    private let size = CGSize(width: 198, height: 50)

    private func presented(at time: Double = 0) -> CapsuleTimeline {
        var timeline = CapsuleTimeline()
        timeline.present(size: size, glow: [0.3, 0.12, 0.19], at: time)
        return timeline
    }

    @Test func hiddenUntilPresented() {
        let timeline = CapsuleTimeline()
        #expect(!timeline.frame(at: 10).isVisible)
        #expect(!presented(at: 1).frame(at: 0.5).isVisible)
    }

    @Test func dropGrowsIntoPill() {
        let timeline = presented()
        let early = timeline.frame(at: 0.1)
        #expect(early.pill.size.width < size.width * 0.5)
        #expect(early.pill.size.height <= early.pill.size.width)
        let settled = timeline.frame(at: 1.0)
        #expect(abs(settled.pill.size.width - size.width) < 1)
        #expect(settled.pill.size.height == size.height)
    }

    @Test func dropRisesToRest() {
        let timeline = presented()
        let start = timeline.frame(at: 0.05).pill.center.y
        let mid = timeline.frame(at: 0.5).pill.center.y
        let late = timeline.frame(at: 3).pill.center.y
        #expect(start > mid)
        #expect(mid > late)
        #expect(abs(start - (Curve.restCenter.y + Curve.riseDistance)) < 1)
        #expect(abs(late - Curve.restCenter.y) < 0.5)
    }

    @Test func appearSendsRipple() throws {
        let timeline = presented()
        let ripple = try #require(timeline.frame(at: 0.5).ripple)
        #expect(abs(ripple.age - (0.5 - Curve.appearRippleDelay)) < 1e-9)
        #expect(ripple.strength == 1)
    }

    @Test func labelFadesInWithBlur() {
        let timeline = presented()
        #expect(timeline.frame(at: 0.05).contentOpacity == 0)
        #expect(timeline.frame(at: 0.05).contentBlur > 6)
        #expect(timeline.frame(at: 0.5).contentOpacity == 1)
        #expect(timeline.frame(at: 0.5).contentBlur == 0)
    }

    @Test func secondarySplitsOffAndPairStaysCentered() {
        var timeline = presented()
        #expect(timeline.frame(at: 1.9).secondary.size == .zero)
        timeline.setSplit(true, at: 2)
        let tucked = timeline.frame(at: 2)
        #expect(tucked.secondaryOpacity == 0)
        #expect(tucked.secondary.rect.maxX <= tucked.pill.rect.maxX + 0.5)

        let settled = timeline.frame(at: 3)
        #expect(settled.isSplit)
        #expect(settled.secondaryOpacity == 1)
        let gap = settled.secondary.rect.minX - settled.pill.rect.maxX
        #expect(abs(gap - Curve.gap) < 0.5)
        let center = (settled.pill.rect.minX + settled.secondary.rect.maxX) / 2
        #expect(abs(center - Curve.restCenter.x) < 0.5)
    }

    @Test func secondaryMergesBackWhenUnsplit() {
        var timeline = presented()
        timeline.setSplit(true, at: 2)
        timeline.setSplit(false, at: 3)
        let frame = timeline.frame(at: 4)
        #expect(!frame.isSplit)
        #expect(frame.secondary.size == .zero)
        #expect(abs(frame.pill.center.x - Curve.restCenter.x) < 0.5)
    }

    @Test func mergeEndsInsideThePillWithoutAJump() {
        var timeline = presented()
        timeline.setSplit(true, at: 2)
        timeline.setSplit(false, at: 3)
        var previous = timeline.frame(at: 3)
        var time = 3.0
        while time < 4 {
            time += 1.0 / 240
            let frame = timeline.frame(at: time)
            let step = abs(frame.secondary.size.width - previous.secondary.size.width)
                + abs(frame.secondary.center.x - previous.secondary.center.x)
            if frame.secondary.size == .zero {
                // The drop may only vanish once it is a bead inside the end cap.
                let bead = previous.secondary.rect
                let cap = previous.pill.rect.insetBy(dx: 10, dy: 10)
                #expect(previous.secondary.size == .zero || cap.contains(bead))
            } else {
                #expect(step < 4)
            }
            previous = frame
        }
        #expect(previous.secondary.size == .zero)
    }

    @Test func hoverGlowsEaseInAndOut() {
        var timeline = presented()
        timeline.setSplit(true, at: 1)
        timeline.setHover(stop: true, transcribe: false, at: 2)
        let rising = timeline.frame(at: 2.05).stopHover
        #expect(rising > 0 && rising < 1)
        #expect(timeline.frame(at: 2.8).stopHover > 0.99)
        #expect(timeline.frame(at: 2.8).transcribeHover == 0)
        timeline.setHover(stop: false, transcribe: true, at: 3)
        let falling = timeline.frame(at: 3.05)
        #expect(falling.stopHover > 0 && falling.stopHover < 1)
        #expect(falling.transcribeHover > 0)
        #expect(!timeline.isSettled(at: 3.5))
        timeline.reduceMotion = true
        #expect(timeline.frame(at: 3.01).transcribeHover == 1)
    }

    @Test func pulseWobblesAndRipplesThenSettles() throws {
        var timeline = presented()
        timeline.pulse(at: 4)
        let wobble = timeline.frame(at: 4.1)
        #expect(wobble.pill.size.height < size.height)
        #expect(wobble.pill.size.width > size.width)
        let ripple = try #require(wobble.ripple)
        #expect(ripple.strength < 1)
        #expect(abs(ripple.age - 0.1) < 1e-9)
        let settled = timeline.frame(at: 6)
        #expect(abs(settled.pill.size.height - size.height) < 0.1)
    }

    @Test func resizeSpringsToNewSize() {
        var timeline = presented()
        timeline.resize(to: CGSize(width: 240, height: 50), at: 2)
        let mid = timeline.frame(at: 2.1).pill.size.width
        #expect(mid > size.width && mid < 240)
        #expect(abs(timeline.frame(at: 3).pill.size.width - 240) < 0.5)
    }

    @Test func resizeRightAfterPresentSnaps() {
        var timeline = presented()
        timeline.resize(to: CGSize(width: 240, height: 50), at: 0.03)
        #expect(abs(timeline.frame(at: 2).pill.size.width - 240) < 0.01)
    }

    @Test func diffusionSoftensFormingPulsingAndLeaving() {
        var timeline = presented()
        #expect(timeline.frame(at: 0.05).diffusion > 0.8)
        #expect(timeline.frame(at: 1).diffusion == 0)
        timeline.pulse(at: 2)
        #expect(timeline.frame(at: 2.05).diffusion > 0.3)
        #expect(timeline.frame(at: 3).diffusion < 0.01)
        timeline.dismiss(at: 4)
        #expect(!timeline.frame(at: 3.9).isDismissing)
        #expect(timeline.frame(at: 4.3).isDismissing)
        #expect(timeline.frame(at: 4.3).diffusion == 1)
        timeline.reduceMotion = true
        #expect(timeline.frame(at: 4.05).diffusion == 0)
    }

    @Test(arguments: [
        ("future", FloatingCapsuleBackgroundStyle.future),
        ("liquid", .future),
        ("liquidGlass", .liquidGlass),
        ("solid", .liquidGlass),
    ])
    func savedStylesMigrate(rawValue: String, style: FloatingCapsuleBackgroundStyle) {
        #expect(FloatingCapsuleBackgroundStyle(rawValue: rawValue) == style)
    }

    @Test func stylesSaveTheirCurrentNames() {
        #expect(FloatingCapsuleBackgroundStyle.allCases.map(\.rawValue) == ["future", "liquidGlass"])
        #expect(FloatingCapsuleBackgroundStyle(rawValue: "unknown") == nil)
    }

    @Test func dismissMergesShrinksAndLifts() {
        var timeline = presented()
        timeline.setSplit(true, at: 1)
        timeline.dismiss(at: 3)
        let start = timeline.frame(at: 3)
        let mid = timeline.frame(at: 3.2)
        #expect(mid.secondary.center.x < start.secondary.center.x)
        #expect(mid.pill.size.width < start.pill.size.width * 0.6)
        #expect(mid.pill.center.y < start.pill.center.y)
        #expect(mid.contentOpacity < 0.1)
        #expect(!mid.isSplit)
        #expect(!timeline.frame(at: 3.001 + Curve.dismissDuration).isVisible)
        #expect(timeline.isSettled(at: 3 + Curve.dismissDuration))
    }

    @Test func eventsAfterDismissAreIgnored() {
        var timeline = presented()
        timeline.dismiss(at: 2)
        let dismissed = timeline
        timeline.setSplit(true, at: 2.1)
        timeline.pulse(at: 2.1)
        timeline.resize(to: CGSize(width: 300, height: 50), at: 2.1)
        #expect(timeline == dismissed)
    }

    @Test func presentAgainDuringDismissRestarts() {
        var timeline = presented()
        timeline.dismiss(at: 2)
        timeline.present(size: size, glow: .zero, at: 2.2)
        #expect(timeline.isPresented)
        #expect(timeline.frame(at: 3.5).isVisible)
    }

    @Test func settlesAfterMotionEnds() {
        var timeline = presented()
        #expect(!timeline.isSettled(at: 1))
        #expect(timeline.isSettled(at: Curve.settleDuration))
        timeline.setSplit(true, at: 5)
        #expect(!timeline.isSettled(at: 6))
        let settled = timeline.frame(at: timeline.settledTime)
        let later = timeline.frame(at: timeline.settledTime + 10)
        #expect(abs(settled.pill.center.y - later.pill.center.y) < 0.25)
        #expect(abs(settled.secondary.center.x - later.secondary.center.x) < 0.01)
    }

    @Test func reduceMotionFadesInPlace() {
        var timeline = presented()
        timeline.reduceMotion = true
        let early = timeline.frame(at: 0.05)
        #expect(early.pill.size == size)
        #expect(early.pill.center == Curve.restCenter)
        #expect(early.ripple == nil)
        #expect(early.visibility > 0 && early.visibility < 1)
        timeline.setSplit(true, at: 1)
        #expect(timeline.frame(at: 1).isSplit)
        timeline.dismiss(at: 2)
        #expect(timeline.frame(at: 2.05).pill.size == size)
        #expect(!timeline.frame(at: 2.001 + Curve.reducedMotionFade).isVisible)
        #expect(Curve.dismissDuration(reduceMotion: true) < Curve.dismissDuration)
    }

    @Test(arguments: [
        (FloatingCapsuleState.Phase.hidden, FloatingCapsuleState.Phase.recording, CapsuleCue.present),
        (.hidden, .error("x"), .present),
        (.recording, .hidden, .dismiss),
        (.copiedToClipboard, .hidden, .dismiss),
        (.hidden, .hidden, .none),
        (.recording, .recording, .none),
        (.recording, .confirmCancel, .resize),
        (.recording, .trimming, .pulse),
        (.recording, .transcribing, .pulse),
        (.trimming, .speeding, .resize),
        (.speeding, .transcribing, .resize),
        (.transcribing, .refining, .pulse),
        (.refining, .copiedToClipboard, .pulse),
        (.copiedToClipboard, .accessibilityPrompt, .resize),
        (.error("a"), .error("b"), .resize),
    ])
    func phaseTransitionsMapToCues(
        old: FloatingCapsuleState.Phase,
        new: FloatingCapsuleState.Phase,
        cue: CapsuleCue
    ) {
        #expect(CapsuleCue.transition(from: old, to: new) == cue)
    }

    @Test func firstPhaseSeenByANewStagePresents() {
        #expect(CapsuleCue.transition(from: .recording, to: .recording, isPresented: false) == .present)
        #expect(CapsuleCue.transition(from: .recording, to: .recording, isPresented: true) == .none)
        #expect(CapsuleCue.transition(from: .recording, to: .hidden, isPresented: false) == .none)
        #expect(CapsuleCue.transition(from: .recording, to: .transcribing, isPresented: true) == .pulse)
    }

    @Test func stagePanelKeepsCapsuleAtClassicHeight() {
        let stageBottom = FloatingCapsuleLayout.bottomOffset(style: .future) + Curve.bottomInset
        #expect(stageBottom == 40)
        #expect(!FloatingCapsuleLayout.usesWindowShadow(style: .future))
        #expect(FloatingCapsuleLayout.dismissDuration(style: .future, reduceMotion: false) >= Curve.dismissDuration)
        if #available(macOS 26.0, *) {
            #expect(FloatingCapsuleLayout.usesStage(style: .liquidGlass))
        }
        let transcript = FloatingCapsuleLayout.panelSize(style: .future, showsLiveTranscript: true)
        #expect(transcript.height > Curve.stageSize.height)
    }
}
