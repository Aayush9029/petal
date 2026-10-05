import AppKit
import UniformTypeIdentifiers

/// Finder icons are slow to load, and the router redraws its nodes often.
@MainActor
enum MacAppIconCache {
    private static var icons: [String: NSImage] = [:]
    private static var menuIcons: [String: NSImage] = [:]

    static func icon(for bundleID: String) -> NSImage {
        if let icon = icons[bundleID] { return icon }
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSWorkspace.shared.icon(for: .application)
        icons[bundleID] = icon
        return icon
    }

    /// Menus draw an image at its own size, so menu items get a 16-point copy.
    static func menuIcon(for bundleID: String) -> NSImage {
        if let icon = menuIcons[bundleID] { return icon }
        let icon = (icon(for: bundleID).copy() as? NSImage) ?? NSImage()
        icon.size = NSSize(width: 16, height: 16)
        menuIcons[bundleID] = icon
        return icon
    }
}
