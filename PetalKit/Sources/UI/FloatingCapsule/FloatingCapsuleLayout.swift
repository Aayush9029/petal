import CoreGraphics
import Shared

/// Window metrics of the floating capsule panel for each capsule style.
public enum FloatingCapsuleLayout {
    private static let transcriptHeight: CGFloat = 112
    private static let transcriptSpacing: CGFloat = 12

    /// Whether the style draws through ``CapsuleStage`` on this system.
    static func usesStage(style: FloatingCapsuleBackgroundStyle) -> Bool {
        CapsuleStage.Material(style: style) != nil
    }

    public static func panelSize(style: FloatingCapsuleBackgroundStyle, showsLiveTranscript: Bool) -> CGSize {
        guard usesStage(style: style) else {
            return CGSize(width: 400, height: showsLiveTranscript ? 178 : 52)
        }
        let stage = CapsuleChoreography.stageSize
        guard showsLiveTranscript else { return stage }
        let transcriptTop = CapsuleChoreography.bottomInset + CapsuleChoreography.pillHeight
            + transcriptSpacing + transcriptHeight
        return CGSize(width: stage.width, height: max(stage.height, transcriptTop + 4))
    }

    /// Distance from the bottom of the visible screen frame to the bottom of the panel.
    /// Every style keeps the capsule itself 40 points above the bottom edge.
    public static func bottomOffset(style: FloatingCapsuleBackgroundStyle) -> CGFloat {
        usesStage(style: style) ? 40 - CapsuleChoreography.bottomInset : 36
    }

    /// The stage glass draws its own shadow, which follows the motion.
    public static func usesWindowShadow(style: FloatingCapsuleBackgroundStyle) -> Bool {
        !usesStage(style: style)
    }

    /// How long the panel stays on screen after it is hidden, so the dismissal can play.
    public static func dismissDuration(style: FloatingCapsuleBackgroundStyle, reduceMotion: Bool) -> Double {
        guard usesStage(style: style) else { return 0 }
        return CapsuleChoreography.dismissDuration(reduceMotion: reduceMotion) + 0.05
    }
}
