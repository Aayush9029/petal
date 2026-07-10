import AppKit
import CoreGraphics
import Foundation

enum AccessibilitySettingsWindowLocator {
    private static let systemSettingsBundleIdentifier = "com.apple.systempreferences"

    static func frontmostWindow() -> AccessibilitySettingsWindowSnapshot? {
        guard let frontmostApplication = NSWorkspace.shared.frontmostApplication,
              frontmostApplication.bundleIdentifier == systemSettingsBundleIdentifier,
              let windowInfo = CGWindowListCopyWindowInfo(
                  [.optionOnScreenOnly, .excludeDesktopElements],
                  .zero
              ) as? [[String: Any]] else {
            return nil
        }

        return windowInfo.compactMap { info in
            snapshot(
                from: info,
                ownerProcessIdentifier: frontmostApplication.processIdentifier
            )
        }
        .max { lhs, rhs in
            lhs.frame.width * lhs.frame.height < rhs.frame.width * rhs.frame.height
        }
    }

    static func fallbackWindow() -> AccessibilitySettingsWindowSnapshot? {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == systemSettingsBundleIdentifier else {
            return nil
        }

        let visibleFrame = NSScreen.main?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1_100, height: 800)
        return AccessibilitySettingsWindowSnapshot(
            frame: visibleFrame.insetBy(dx: 80, dy: 70),
            visibleFrame: visibleFrame
        )
    }

    private static func snapshot(
        from info: [String: Any],
        ownerProcessIdentifier: pid_t
    ) -> AccessibilitySettingsWindowSnapshot? {
        guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
              ownerPID == ownerProcessIdentifier,
              let layer = info[kCGWindowLayer as String] as? Int,
              layer == 0,
              let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] else {
            return nil
        }

        let coreGraphicsFrame = CGRect(
            x: bounds["X"] ?? 0,
            y: bounds["Y"] ?? 0,
            width: bounds["Width"] ?? 0,
            height: bounds["Height"] ?? 0
        )
        guard coreGraphicsFrame.width > 320, coreGraphicsFrame.height > 240 else {
            return nil
        }

        let geometry = appKitGeometry(from: coreGraphicsFrame)
        return AccessibilitySettingsWindowSnapshot(
            frame: geometry.frame,
            visibleFrame: geometry.visibleFrame
        )
    }

    private static func appKitGeometry(
        from coreGraphicsFrame: CGRect
    ) -> (frame: CGRect, visibleFrame: CGRect) {
        let screens = NSScreen.screens.compactMap { screen -> (
            frame: CGRect,
            visibleFrame: CGRect,
            coreGraphicsBounds: CGRect
        )? in
            guard let screenNumber = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber else {
                return nil
            }

            return (
                frame: screen.frame,
                visibleFrame: screen.visibleFrame,
                coreGraphicsBounds: CGDisplayBounds(CGDirectDisplayID(screenNumber.uint32Value))
            )
        }

        guard let matchedScreen = screens
            .filter({ $0.coreGraphicsBounds.intersects(coreGraphicsFrame) })
            .max(by: { lhs, rhs in
                intersectionArea(lhs.coreGraphicsBounds, coreGraphicsFrame)
                    < intersectionArea(rhs.coreGraphicsBounds, coreGraphicsFrame)
            }) else {
            let visibleFrame = NSScreen.main?.visibleFrame
                ?? CGRect(origin: .zero, size: coreGraphicsFrame.size)
            return (frame: coreGraphicsFrame, visibleFrame: visibleFrame)
        }

        let localX = coreGraphicsFrame.minX - matchedScreen.coreGraphicsBounds.minX
        let localY = coreGraphicsFrame.minY - matchedScreen.coreGraphicsBounds.minY
        return (
            frame: CGRect(
                x: matchedScreen.frame.minX + localX,
                y: matchedScreen.frame.maxY - localY - coreGraphicsFrame.height,
                width: coreGraphicsFrame.width,
                height: coreGraphicsFrame.height
            ),
            visibleFrame: matchedScreen.visibleFrame
        )
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        return intersection.width * intersection.height
    }
}
