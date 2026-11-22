import CoreGraphics
import Shared

public enum FloatingCapsuleLayout {
    private static let transcriptHeight: CGFloat = 112
    private static let transcriptSpacing: CGFloat = 12

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

    public static func bottomOffset(style: FloatingCapsuleBackgroundStyle) -> CGFloat {
        usesStage(style: style) ? 40 - CapsuleChoreography.bottomInset : 36
    }

    // The shader supplies its own moving shadow.
    public static func usesWindowShadow(style: FloatingCapsuleBackgroundStyle) -> Bool {
        !usesStage(style: style)
    }

    public static func dismissDuration(style: FloatingCapsuleBackgroundStyle, reduceMotion: Bool) -> Double {
        guard usesStage(style: style) else { return 0 }
        return CapsuleChoreography.dismissDuration(reduceMotion: reduceMotion) + 0.05
    }
}
