import AppKit
import Observation
import Shared

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    // The rendered glyphs are 18pt wide; a snug fixed width keeps the item from
    // reserving the wide slot the previous SF Symbol used.
    private static let iconWidth: CGFloat = 22

    private let statusItem: NSStatusItem
    private let dropOverlay: DropOverlayView
    private let viewModel: MenuBarContentViewModel
    private let menu = NSMenu()

    private var animationTimer: Timer?
    private var animationTick = 0
    private var smoothedLevel: Double = 0

    init(viewModel: MenuBarContentViewModel) {
        self.viewModel = viewModel
        self.statusItem = NSStatusBar.system.statusItem(withLength: Self.iconWidth)
        self.dropOverlay = DropOverlayView(frame: .zero)
        super.init()

        if let button = statusItem.button {
            dropOverlay.frame = button.bounds
            dropOverlay.autoresizingMask = [.width, .height]
            dropOverlay.onDropURLs = { [weak self] urls in self?.handleDroppedURLs(urls) }
            button.addSubview(dropOverlay)
        }

        menu.delegate = self
        statusItem.menu = menu
        observeViewModel()
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func observeViewModel() {
        withObservationTracking {
            applyStatus()
        } onChange: {
            Task { @MainActor [weak self] in
                self?.observeViewModel()
            }
        }
    }

    private func applyStatus() {
        guard let button = statusItem.button else { return }
        // Reading these inside observation tracking re-runs applyStatus when the
        // session state changes. Audio level is deliberately not read here — it
        // is sampled per frame in renderAnimationFrame so level updates don't
        // churn observation.
        let state = viewModel.iconState
        button.toolTip = "Petal - \(viewModel.statusTitle)"

        if state.isAnimated {
            startAnimating()
            renderAnimationFrame()
        } else {
            stopAnimating()
            button.image = staticImage(for: state)
        }
    }

    // MARK: - Pixel animation

    private func startAnimating() {
        guard animationTimer == nil else { return }
        animationTick = 0
        let timer = Timer(timeInterval: 1.0 / 24.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.renderAnimationFrame() }
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    private func stopAnimating() {
        animationTimer?.invalidate()
        animationTimer = nil
        smoothedLevel = 0
    }

    private func renderAnimationFrame() {
        guard let button = statusItem.button else { return }
        animationTick += 1
        switch viewModel.iconState {
        case .recording:
            // Fast attack, slow decay so the bars jump up with speech and settle
            // gently — no jittery flicker. (The audio level is already enveloped
            // upstream; this keeps the visual calm and matched.)
            let target = viewModel.audioLevel
            let coefficient = target > smoothedLevel ? 0.5 : 0.2
            smoothedLevel += (target - smoothedLevel) * coefficient
            button.image = MenuBarIconRenderer.recording(level: smoothedLevel)
        case .working:
            button.image = MenuBarIconRenderer.working(tick: animationTick)
        case .idle, .error:
            stopAnimating()
            button.image = staticImage(for: viewModel.iconState)
        }
    }

    private func staticImage(for state: MenuBarIconState) -> NSImage? {
        switch state {
        case .idle:
            return MenuBarIconRenderer.idlePetal
        case .error:
            return MenuBarIconRenderer.error()
        case .recording, .working:
            return nil
        }
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
        buildStatusSection(into: menu)
        menu.addItem(.separator())
        buildPermissionsSection(into: menu)
        buildHistorySection(into: menu)
        menu.addItem(.separator())
        buildAppSection(into: menu)
        menu.addItem(.separator())
        buildQuitSection(into: menu)
    }

    private func buildStatusSection(into menu: NSMenu) {
        menu.addItem(disabledItem(viewModel.statusTitle))

        if viewModel.isRecording {
            menu.addItem(actionItem("Stop Recording", action: #selector(stopRecording)))
        }

        if let error = viewModel.statusErrorMessage {
            menu.addItem(disabledItem(error))
        }

        if !viewModel.isRecording, let message = viewModel.transientMessage {
            menu.addItem(disabledItem(message))
        }
    }

    private func buildPermissionsSection(into menu: NSMenu) {
        guard viewModel.shouldShowPermissionsSection else { return }
        if viewModel.needsMicrophonePermission {
            menu.addItem(actionItem("Allow Microphone Access", action: #selector(requestMicrophonePermission)))
        }
        if viewModel.needsAccessibilityPermission {
            menu.addItem(actionItem("Allow Accessibility Access", action: #selector(requestAccessibilityPermission)))
        }
    }

    private func buildHistorySection(into menu: NSMenu) {
        guard viewModel.shouldShowHistoryMenu else { return }

        let historyItem = NSMenuItem(title: "History", action: nil, keyEquivalent: "")
        let historyMenu = NSMenu()

        if viewModel.historyMenuItems.isEmpty {
            historyMenu.addItem(disabledItem("No transcripts yet"))
        } else {
            for entry in viewModel.historyMenuItems {
                let item = actionItem("\(entry.title) - \(entry.subtitle)", action: #selector(copyHistoryEntry(_:)))
                item.identifier = NSUserInterfaceItemIdentifier(entry.id.uuidString)
                historyMenu.addItem(item)
            }
        }

        historyItem.submenu = historyMenu
        menu.addItem(historyItem)
    }

    private func buildAppSection(into menu: NSMenu) {
        if viewModel.showsCheckForUpdates {
            let item = actionItem("Check for Updates…", action: #selector(checkForUpdates))
            item.isEnabled = viewModel.canCheckForUpdates
            menu.addItem(item)
        }

        menu.addItem(actionItem("About Petal", action: #selector(showAbout)))
        menu.addItem(actionItem("Settings", action: #selector(openSettings), key: ",", modifiers: [.command]))
    }

    private func buildQuitSection(into menu: NSMenu) {
        menu.addItem(actionItem("Quit Petal", action: #selector(quit), key: "q", modifiers: [.command]))
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func actionItem(
        _ title: String,
        action: Selector,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = []
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        if !modifiers.isEmpty {
            item.keyEquivalentModifierMask = modifiers
        }
        return item
    }

    @objc private func requestMicrophonePermission() {
        viewModel.requestMicrophonePermission()
    }

    @objc private func requestAccessibilityPermission() {
        viewModel.requestAccessibilityPermission()
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

    @objc private func copyHistoryEntry(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.identifier?.rawValue,
            let id = UUID(uuidString: rawValue)
        else { return }
        viewModel.copyHistoryEntry(id)
    }
}

@MainActor
private final class DropOverlayView: NSView {
    var onDropURLs: (([URL]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    override func mouseDown(with event: NSEvent) {
        superview?.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        superview?.mouseUp(with: event)
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
}
