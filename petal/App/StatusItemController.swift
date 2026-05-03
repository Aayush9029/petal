import AppKit
import Shared

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let statusView: DropStatusItemView
    private let viewModel: MenuBarContentViewModel
    private let menu = NSMenu()
    private var refreshTimer: Timer?

    init(viewModel: MenuBarContentViewModel) {
        self.viewModel = viewModel
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusView = DropStatusItemView(frame: NSRect(x: 0, y: 0, width: 28, height: NSStatusBar.system.thickness))
        super.init()

        statusView.onClick = { [weak self] in
            self?.showMenu()
        }
        statusView.onDropURLs = { [weak self] urls in
            self?.handleDroppedURLs(urls)
        }
        statusItem.view = statusView
        menu.delegate = self
        refresh()

        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.refreshTimer = timer
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func refresh() {
        statusView.symbolName = viewModel.statusSymbolName
        statusView.toolTip = "Petal - \(viewModel.statusTitle)"
        statusItem.length = 28
        statusView.needsDisplay = true
    }

    private func showMenu() {
        rebuildMenu()
        statusView.isMenuHighlighted = true
        statusView.needsDisplay = true
        statusItem.popUpMenu(menu)
        statusView.isMenuHighlighted = false
        statusView.needsDisplay = true
    }

    private func handleDroppedURLs(_ urls: [URL]) {
        switch AudioFileDropValidator.validate(urls) {
        case let .accepted(url):
            Task { await viewModel.transcribeDroppedAudioFile(url) }
        case let .rejected(error):
            viewModel.droppedAudioFileRejected(error)
        }
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let statusItem = NSMenuItem(title: viewModel.statusTitle, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        if viewModel.isRecording {
            menu.addItem(NSMenuItem(title: "Stop Recording", action: #selector(stopRecording), keyEquivalent: ""))
        }

        if let error = viewModel.statusErrorMessage {
            let item = NSMenuItem(title: error, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        if !viewModel.isRecording, let message = viewModel.transientMessage {
            let item = NSMenuItem(title: message, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(.separator())

        if viewModel.shouldShowPermissionsSection {
            if viewModel.needsMicrophonePermission {
                menu.addItem(NSMenuItem(title: "Grant Microphone Access", action: #selector(requestMicrophonePermission), keyEquivalent: ""))
            }

            if viewModel.needsAccessibilityPermission {
                menu.addItem(NSMenuItem(title: "Enable Accessibility Access", action: #selector(requestAccessibilityPermission), keyEquivalent: ""))
            }
        }

        if viewModel.shouldShowHistoryMenu {
            let historyItem = NSMenuItem(title: "History", action: nil, keyEquivalent: "")
            let historyMenu = NSMenu()
            if viewModel.historyMenuItems.isEmpty {
                let emptyItem = NSMenuItem(title: "No transcripts yet", action: nil, keyEquivalent: "")
                emptyItem.isEnabled = false
                historyMenu.addItem(emptyItem)
            } else {
                for item in viewModel.historyMenuItems {
                    let menuItem = NSMenuItem(
                        title: "\(item.title) - \(item.subtitle)",
                        action: #selector(copyHistoryEntry(_:)),
                        keyEquivalent: ""
                    )
                    menuItem.identifier = NSUserInterfaceItemIdentifier(item.id.uuidString)
                    historyMenu.addItem(menuItem)
                }
            }
            historyItem.submenu = historyMenu
            menu.addItem(historyItem)
        }

        menu.addItem(.separator())

        if viewModel.showsCheckForUpdates {
            let item = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: "")
            item.isEnabled = viewModel.canCheckForUpdates
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem(title: "About Petal", action: #selector(showAbout), keyEquivalent: ""))

        let settingsItem = NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = [.command]

        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Petal", action: #selector(quit), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        menu.addItem(quitItem)

        for item in menu.items where item.action != nil {
            item.target = self
        }
        for item in menu.items.flatMap({ $0.submenu?.items ?? [] }) where item.action != nil {
            item.target = self
        }
    }

    @objc private func requestMicrophonePermission() {
        viewModel.requestMicrophonePermission()
    }

    @objc private func requestAccessibilityPermission() {
        viewModel.requestAccessibilityPermission()
    }

    @objc private func copyHistoryEntry(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.identifier?.rawValue,
            let id = UUID(uuidString: rawValue)
        else { return }
        viewModel.copyHistoryEntry(id)
    }

    @objc private func stopRecording() {
        viewModel.stopRecording()
    }

    @objc private func checkForUpdates() {
        viewModel.checkForUpdates()
    }

    @objc private func showAbout() {
        viewModel.showAbout()
    }

    @objc private func openSettings() {
        viewModel.openSettings()
    }

    @objc private func quit() {
        viewModel.quit()
    }
}

@MainActor
private final class DropStatusItemView: NSControl {
    var symbolName = "waveform.badge.mic"
    var isMenuHighlighted = false
    var onClick: (() -> Void)?
    var onDropURLs: (([URL]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 28, height: NSStatusBar.system.thickness)
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let objects = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )
        let urls = objects?.compactMap { object -> URL? in
            if let url = object as? URL { return url }
            return (object as? NSURL).map { $0 as URL }
        } ?? []
        onDropURLs?(urls)
        return !urls.isEmpty
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if isMenuHighlighted {
            NSColor.selectedMenuItemColor.setFill()
            bounds.fill()
        }

        let iconColor = isMenuHighlighted ? NSColor.selectedMenuItemTextColor : statusItemForegroundColor
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
            .applying(.init(hierarchicalColor: iconColor))
        let image = (
            NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
                ?? NSImage(systemSymbolName: "waveform.badge.mic", accessibilityDescription: nil)
        )?.withSymbolConfiguration(configuration)

        let imageSize = image?.size ?? NSSize(width: 16, height: 16)
        let imageRect = NSRect(
            x: bounds.midX - imageSize.width / 2,
            y: bounds.midY - imageSize.height / 2,
            width: imageSize.width,
            height: imageSize.height
        )
        image?.draw(in: imageRect)
    }

    private var statusItemForegroundColor: NSColor {
        let appearance = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua, .vibrantDark, .vibrantLight])
        switch appearance {
        case .darkAqua, .vibrantDark:
            return .white
        default:
            return .labelColor
        }
    }
}
