import AppKit

@MainActor
final class AccessibilityGuideWindowController: NSWindowController {
    private let windowSize = NSSize(width: 560, height: 144)

    init(application: AccessibilityGuideApplication, onClose: @escaping () -> Void) {
        let window = AccessibilityGuidePanel(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)

        configure(window)
        window.contentView = makeBackgroundView(
            contentView: AccessibilityGuideContentView(
                application: application,
                onClose: onClose
            )
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present(settingsFrame: CGRect, visibleFrame: CGRect) {
        guard let window else { return }
        let targetOrigin = anchoredOrigin(
            settingsFrame: settingsFrame,
            visibleFrame: visibleFrame
        )

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            window.alphaValue = 1
            window.setFrameOrigin(targetOrigin)
            window.orderFrontRegardless()
            return
        }

        window.alphaValue = 0
        window.setFrameOrigin(NSPoint(x: targetOrigin.x, y: targetOrigin.y - 10))
        window.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
            window.animator().setFrameOrigin(targetOrigin)
        }
    }

    func updatePosition(settingsFrame: CGRect, visibleFrame: CGRect) {
        guard let window else { return }
        let origin = anchoredOrigin(
            settingsFrame: settingsFrame,
            visibleFrame: visibleFrame
        )
        window.setFrameOrigin(origin)
        window.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }

    override func close() {
        window?.orderOut(nil)
        super.close()
    }

    private func configure(_ window: NSWindow) {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .statusBar
        window.hasShadow = true
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary,
        ]
    }

    private func makeBackgroundView(contentView: NSView) -> NSView {
        let frame = NSRect(origin: .zero, size: windowSize)
        contentView.frame = frame
        contentView.autoresizingMask = [.width, .height]

        if #available(macOS 26.0, *),
           !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            let glassView = NSGlassEffectView(frame: frame)
            glassView.style = .regular
            glassView.cornerRadius = 24
            glassView.contentView = contentView
            return glassView
        }

        let materialView = NSVisualEffectView(frame: frame)
        materialView.material = .hudWindow
        materialView.blendingMode = .behindWindow
        materialView.state = .active
        materialView.wantsLayer = true
        materialView.layer?.cornerRadius = 24
        materialView.layer?.masksToBounds = true
        materialView.layer?.borderWidth = 0.5
        materialView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.22).cgColor
        materialView.addSubview(contentView)
        return materialView
    }

    private func anchoredOrigin(settingsFrame: CGRect, visibleFrame: CGRect) -> NSPoint {
        let sidebarWidth = min(220, settingsFrame.width * 0.28)
        let contentMinX = settingsFrame.minX + sidebarWidth
        let contentWidth = max(settingsFrame.width - sidebarWidth, windowSize.width)
        let preferredX = contentMinX + ((contentWidth - windowSize.width) / 2)
        let preferredY = settingsFrame.minY + 18
        let edgeInset: CGFloat = 10

        return NSPoint(
            x: min(
                max(preferredX, visibleFrame.minX + edgeInset),
                visibleFrame.maxX - windowSize.width - edgeInset
            ),
            y: min(
                max(preferredY, visibleFrame.minY + edgeInset),
                visibleFrame.maxY - windowSize.height - edgeInset
            )
        )
    }
}
