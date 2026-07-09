import AppKit

@MainActor
enum WindowRuntime {
    static let shared = WindowRuntimeImpl()
}

@MainActor
final class WindowRuntimeImpl {
    private var controllers: [String: NSWindowController] = [:]
    private var delegates: [String: WindowCloseDelegate] = [:]

    func show(config: WindowConfig, content: () -> NSView, onClose: @escaping () -> Void) {
        if let existing = controllers[config.id], existing.window?.isVisible == true {
            bringToFront(id: config.id)
            return
        }

        let window: NSWindow
        switch config.style {
        case let .chromeless(options):
            window = makeChromelessWindow(config: config, options: options, contentView: content())
        case let .titled(options):
            window = makeTitledWindow(config: config, options: options, contentView: content())
        }

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

    func bringToFront(id: String) {
        guard let window = controllers[id]?.window else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close(id: String) {
        controllers[id]?.window?.close()
    }

    func closeAll(id: String) {
        for window in NSApp.windows where window.identifier?.rawValue == id {
            if window !== controllers[id]?.window {
                window.close()
            }
        }
        close(id: id)
    }

    func isVisible(id: String) -> Bool {
        controllers[id]?.window?.isVisible ?? false
    }

    // MARK: - Window Factories

    private func makeChromelessWindow(config: WindowConfig, options: ChromelessOptions, contentView: NSView) -> NSWindow {
        var styleMask: NSWindow.StyleMask = [.titled, .fullSizeContentView]
        if !options.hidesCloseButton {
            styleMask.insert(.closable)
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
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.isReleasedWhenClosed = config.isReleasedWhenClosed
        window.tabbingMode = config.tabbingMode
        window.animationBehavior = config.animationBehavior
        window.collectionBehavior = config.collectionBehavior

        if options.isFloating {
            window.level = .floating
        }

        if options.hidesCloseButton {
            window.standardWindowButton(.closeButton)?.isHidden = true
        }
        if options.hidesMiniaturizeButton {
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        }
        if options.hidesZoomButton {
            window.standardWindowButton(.zoomButton)?.isHidden = true
        }

        if let effect = options.visualEffect {
            let container = NSView(frame: NSRect(origin: .zero, size: config.size))

            let visualEffectView = NSVisualEffectView()
            visualEffectView.material = effect.material
            visualEffectView.blendingMode = effect.blendingMode
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

            window.contentView = container
        } else {
            window.contentView = contentView
        }

        window.setContentSize(config.size)
        return window
    }

    private func makeTitledWindow(config: WindowConfig, options: TitledOptions, contentView: NSView) -> NSWindow {
        var styleMask: NSWindow.StyleMask = [.titled, .fullSizeContentView, .miniaturizable, .resizable]
        if options.showsCloseButton {
            styleMask.insert(.closable)
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
        window.isReleasedWhenClosed = config.isReleasedWhenClosed
        window.tabbingMode = config.tabbingMode
        window.animationBehavior = config.animationBehavior
        window.collectionBehavior = config.collectionBehavior
        window.contentView = contentView
        window.minSize = config.size

        if let toolbarStyle = options.toolbarStyle {
            window.toolbarStyle = toolbarStyle
        }

        window.setContentSize(config.size)
        return window
    }
}

// MARK: - Window Close Delegate

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
