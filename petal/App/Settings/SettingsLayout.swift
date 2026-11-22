import CoreGraphics

enum SettingsLayout {
    static let sidebarWidth: CGFloat = 205
    static let contentWidth: CGFloat = 500
    static let contentPadding: CGFloat = 22
    static var detailWidth: CGFloat { contentWidth + contentPadding * 2 }
    static var windowWidth: CGFloat { sidebarWidth + detailWidth }
}
