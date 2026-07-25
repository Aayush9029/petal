import AppKit

/// Borderless, non-activating panel instead of `NSPopover` (own glass chrome, not the popover's arrow) or `NSMenu` (hosts live SwiftUI controls).
final class PopupPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
