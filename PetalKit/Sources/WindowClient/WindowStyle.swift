import AppKit
import CasePaths

@CasePathable
public enum WindowStyle: Sendable {
    case chromeless(ChromelessOptions = .init())
    case titled(TitledOptions = .init())
}

public struct ChromelessOptions: Sendable {
    public var hidesCloseButton: Bool
    public var hidesMiniaturizeButton: Bool
    public var hidesZoomButton: Bool
    public var isFloating: Bool
    public var visualEffect: VisualEffectConfig?

    public init(
        hidesCloseButton: Bool = false,
        hidesMiniaturizeButton: Bool = true,
        hidesZoomButton: Bool = true,
        isFloating: Bool = true,
        visualEffect: VisualEffectConfig? = nil
    ) {
        self.hidesCloseButton = hidesCloseButton
        self.hidesMiniaturizeButton = hidesMiniaturizeButton
        self.hidesZoomButton = hidesZoomButton
        self.isFloating = isFloating
        self.visualEffect = visualEffect
    }
}

public struct TitledOptions: Sendable {
    public var showsCloseButton: Bool
    public var toolbarStyle: NSWindow.ToolbarStyle?
    /// When set, the window keeps its width and only its height resizes, down to this value.
    public var minHeightWithFixedWidth: CGFloat?

    public init(
        showsCloseButton: Bool = true,
        toolbarStyle: NSWindow.ToolbarStyle? = nil,
        minHeightWithFixedWidth: CGFloat? = nil
    ) {
        self.showsCloseButton = showsCloseButton
        self.toolbarStyle = toolbarStyle
        self.minHeightWithFixedWidth = minHeightWithFixedWidth
    }
}

public struct VisualEffectConfig: Sendable {
    public var material: NSVisualEffectView.Material
    public var blendingMode: NSVisualEffectView.BlendingMode

    public init(
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    ) {
        self.material = material
        self.blendingMode = blendingMode
    }
}
