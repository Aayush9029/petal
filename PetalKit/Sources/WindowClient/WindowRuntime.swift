import AppKit

@MainActor
final class WindowRuntime {
    static let shared = WindowRuntime()

    private var controllers: [String: NSWindowController] = [:]
    private var delegates: [String: WindowCloseDelegate] = [:]

    func show(config: WindowConfig, content: () -> NSView, onClose: @escaping () -> Void) {
        if let window = controllers[config.id]?.window {
            if window.isMiniaturized { window.deminiaturize(nil) }
            if let frame = (window.screen ?? NSScreen.main)?.visibleFrame, !frame.contains(window.frame) {
                window.setFrameOrigin(CGPoint(x: frame.midX - window.frame.width / 2, y: frame.midY - window.frame.height / 2))
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = makeWindow(config: config, contentView: content())
        let delegate = WindowCloseDelegate { [weak self] closedWindow in
            guard let self else { return }
            if let id = self.controllers.first(where: { $0.value.window === closedWindow })?.key {
                self.controllers.removeValue(forKey: id)
                self.delegates.removeValue(forKey: id)
            }
            onClose()
        }
        delegates[config.id] = delegate
        window.delegate = delegate

        let controller = NSWindowController(window: window)
        controllers[config.id] = controller

        NSRunningApplication.current.activate(options: [.activateAllWindows])
        controller.showWindow(nil)
        window.center()
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close(id: String) {
        controllers[id]?.window?.close()
    }

    private func makeWindow(config: WindowConfig, contentView: NSView) -> NSWindow {
        var styleMask: NSWindow.StyleMask = [.titled, .fullSizeContentView]
        switch config.style {
        case .chromeless(let showsCloseButton, _, _):
            if showsCloseButton { styleMask.insert(.closable) }
        case .titled:
            styleMask.formUnion([.miniaturizable, .resizable, .closable])
        }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: config.size),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier(config.id)
        window.title = config.title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.animationBehavior = config.animationBehavior
        window.collectionBehavior = config.collectionBehavior
        window.contentView = contentView

        switch config.style {
        case let .chromeless(showsCloseButton, floating, usesHUD):
            window.isMovableByWindowBackground = true
            window.backgroundColor = .clear
            window.isOpaque = false
            if floating { window.level = .floating }
            window.standardWindowButton(.closeButton)?.isHidden = !showsCloseButton
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            if usesHUD {
                window.contentView = hudView(containing: contentView, size: config.size)
            }
        case .titled(let minimumHeight):
            window.contentMinSize = CGSize(width: config.size.width, height: minimumHeight)
            window.contentMaxSize = CGSize(width: config.size.width, height: .greatestFiniteMagnitude)
            window.toolbarStyle = .unified
        }
        window.setContentSize(config.size)
        return window
    }

    private func hudView(containing contentView: NSView, size: CGSize) -> NSView {
        let container = NSView(frame: NSRect(origin: .zero, size: size))

        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false

        contentView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(visualEffectView)
        container.addSubview(contentView)

        NSLayoutConstraint.activate([
            visualEffectView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            visualEffectView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            visualEffectView.topAnchor.constraint(equalTo: container.topAnchor),
            visualEffectView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: container.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return container
    }
}

@MainActor
private final class WindowCloseDelegate: NSObject {
    let onClose: (NSWindow) -> Void

    init(onClose: @escaping (NSWindow) -> Void) {
        self.onClose = onClose
    }
}

extension WindowCloseDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        window.delegate = nil
        onClose(window)
    }
}
