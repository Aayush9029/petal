import AppKit
import UniformTypeIdentifiers

/// Finder icons are slow to load, and the router redraws its nodes often.
@MainActor
enum MacAppIconCache {
    private static var icons: [String: NSImage] = [:]

    static func icon(for bundleID: String) -> NSImage {
        if let icon = icons[bundleID] { return icon }
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSWorkspace.shared.icon(for: .application)
        icons[bundleID] = icon
        return icon
    }
}
