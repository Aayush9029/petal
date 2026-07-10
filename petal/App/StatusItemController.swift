import AppKit
import Observation
import Shared
import SwiftUI

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    // The rendered glyphs are 18pt wide; a snug fixed width keeps the item from
    // reserving the wide slot the previous SF Symbol used.
    private static let iconWidth: CGFloat = 22

    private let statusItem: NSStatusItem
    private let dropOverlay: DropOverlayView
    private let viewModel: MenuBarContentViewModel
    private let popover = NSPopover()
    private var lastPopoverClose: Date = .distantPast

    private var animationTimer: Timer?
    private var animationTick = 0
    private var smoothedLevel: Double = 0
    private var isDropTargeted = false

    init(viewModel: MenuBarContentViewModel) {
        self.viewModel = viewModel
        self.statusItem = NSStatusBar.system.statusItem(withLength: Self.iconWidth)
        self.dropOverlay = DropOverlayView(frame: .zero)
        super.init()

        configurePopover()

        if let button = statusItem.button {
            dropOverlay.frame = button.bounds
            dropOverlay.autoresizingMask = [.width, .height]
            dropOverlay.onDropURLs = { [weak self] urls in self?.handleDroppedURLs(urls) }
            dropOverlay.onDropTargetedChanged = { [weak self] isTargeted in
                self?.dropTargetedChanged(isTargeted)
            }
            dropOverlay.onClick = { [weak self] in self?.togglePopover() }
            button.addSubview(dropOverlay)
        }

        observeViewModel()
    }

    // MARK: - Popover

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let host = NSHostingController(
            rootView: MenuBarPopover(viewModel: viewModel, dismiss: { [weak self] in
                self?.popover.performClose(nil)
            })
        )
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        // The transient popover's own monitor closes it on the click that also
        // reaches us; ignore that click so we don't immediately reopen.
        if Date().timeIntervalSince(lastPopoverClose) < 0.25 { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    func popoverDidClose(_ notification: Notification) {
        lastPopoverClose = Date()
    }

    // MARK: - Status observation

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
        if isDropTargeted {
            stopAnimating()
            button.toolTip = "Drop audio file to transcribe"
            button.image = MenuBarIconRenderer.dropTarget
            return
        }

        // Reading these inside observation tracking re-runs applyStatus when the
        // session state changes. Audio level is deliberately not read here — it
        // is sampled per frame in renderAnimationFrame so level updates don't
        // churn observation.
        let state = viewModel.iconState
        button.toolTip = "Petal — \(viewModel.statusTitle)"

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
        Task { await viewModel.audioFilesDropped(urls) }
    }

    private func dropTargetedChanged(_ isTargeted: Bool) {
        guard isDropTargeted != isTargeted else { return }
        isDropTargeted = isTargeted
        applyStatus()
    }
}

@MainActor
private final class DropOverlayView: NSView {
    var onDropURLs: (([URL]) -> Void)?
    var onDropTargetedChanged: ((Bool) -> Void)?
    var onClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDropTargetedChanged?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDropTargetedChanged?(false)
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
        onDropTargetedChanged?(false)
        onDropURLs?(urls)
        return !urls.isEmpty
    }
}
