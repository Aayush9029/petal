import AppKit

public struct WindowConfig: Sendable {
    public let id: String
    let title: String
    let style: WindowStyle
    let size: CGSize
    var animationBehavior: NSWindow.AnimationBehavior = .default
    var collectionBehavior: NSWindow.CollectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
}

enum WindowStyle: Sendable {
    case chromeless(showsCloseButton: Bool, floating: Bool, usesHUD: Bool)
    case titled(minimumHeight: CGFloat)
}
