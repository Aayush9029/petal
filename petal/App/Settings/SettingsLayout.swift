import CoreGraphics

/// The Settings window has a fixed width. The detail column fits two model cards side by side.
enum SettingsLayout {
    static let sidebarWidth: CGFloat = 205
    static let contentWidth: CGFloat = 500
    static let contentPadding: CGFloat = 22
    static var detailWidth: CGFloat { contentWidth + contentPadding * 2 }
    static var windowWidth: CGFloat { sidebarWidth + detailWidth }
}
