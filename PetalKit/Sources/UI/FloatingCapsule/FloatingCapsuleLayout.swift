import CoreGraphics
import Shared

/// Window metrics of the floating capsule panel for each capsule style.
public enum FloatingCapsuleLayout {
    private static let transcriptHeight: CGFloat = 112
    private static let transcriptSpacing: CGFloat = 12

    public static func panelSize(style: FloatingCapsuleBackgroundStyle, showsLiveTranscript: Bool) -> CGSize {
        switch style {
        case .liquid:
            let stage = LiquidCapsuleChoreography.stageSize
            guard showsLiveTranscript else { return stage }
            let transcriptTop = LiquidCapsuleChoreography.bottomInset + LiquidCapsuleChoreography.pillHeight
                + transcriptSpacing + transcriptHeight
            return CGSize(width: stage.width, height: max(stage.height, transcriptTop + 4))
        case .liquidGlass, .solid:
            return CGSize(width: 400, height: showsLiveTranscript ? 178 : 52)
        }
    }

    /// Distance from the bottom of the visible screen frame to the bottom of the panel.
    /// Every style keeps the capsule itself 40 points above the bottom edge.
    public static func bottomOffset(style: FloatingCapsuleBackgroundStyle) -> CGFloat {
        switch style {
        case .liquid:
            return 40 - LiquidCapsuleChoreography.bottomInset
        case .liquidGlass, .solid:
            return 36
        }
    }

    /// The liquid glass draws its own contact shadow, which follows the motion.
    public static func usesWindowShadow(style: FloatingCapsuleBackgroundStyle) -> Bool {
        style != .liquid
    }

    /// How long the panel stays on screen after it is hidden, so the dismissal can play.
    public static func dismissDuration(style: FloatingCapsuleBackgroundStyle, reduceMotion: Bool) -> Double {
        switch style {
        case .liquid:
            return LiquidCapsuleChoreography.dismissDuration(reduceMotion: reduceMotion) + 0.05
        case .liquidGlass, .solid:
            return 0
        }
    }
}
