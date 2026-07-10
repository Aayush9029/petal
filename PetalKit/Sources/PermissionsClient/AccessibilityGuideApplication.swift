import AppKit
import Foundation

@MainActor
struct AccessibilityGuideApplication {
    let displayName: String
    let bundleURL: URL
    let icon: NSImage

    static func current(bundle: Bundle = .main) -> Self {
        let bundleURL = applicationBundleURL(for: bundle)
        let rawDisplayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String
            ?? bundleURL.deletingPathExtension().lastPathComponent
        let displayName = rawDisplayName == rawDisplayName.lowercased()
            ? rawDisplayName.localizedCapitalized
            : rawDisplayName
        let icon = NSWorkspace.shared.icon(forFile: bundleURL.path)
        icon.size = NSSize(width: 64, height: 64)

        return Self(displayName: displayName, bundleURL: bundleURL, icon: icon)
    }

    static func applicationBundleURL(for bundle: Bundle) -> URL {
        applicationBundleURL(
            executableURL: bundle.executableURL,
            fallbackURL: bundle.bundleURL
        )
    }

    static func applicationBundleURL(executableURL: URL?, fallbackURL: URL) -> URL {
        var candidate = executableURL?.deletingLastPathComponent()

        while let url = candidate {
            if url.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
                return url.standardizedFileURL
            }

            let parent = url.deletingLastPathComponent()
            guard parent != url else { break }
            candidate = parent
        }

        return fallbackURL.standardizedFileURL
    }
}
