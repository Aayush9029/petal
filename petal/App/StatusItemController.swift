import AppKit
import Observation
import Shared
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private static let iconWidth: CGFloat = 22

    private let statusItem: NSStatusItem
    private let dropOverlay: DropOverlayView
    private let viewModel: MenuBarContentViewModel
    private var popup: PopupPanelController?

    private var animationTimer: Timer?
    private var animationTick = 0
    private var smoothedLevel: Double = 0
    private var isDropTargeted = false

    init(viewModel: MenuBarContentViewModel) {
        self.viewModel = viewModel
        self.statusItem = NSStatusBar.system.statusItem(withLength: Self.iconWidth)
        self.dropOverlay = DropOverlayView(frame: .zero)
        super.init()

        if let button = statusItem.button {
            dropOverlay.frame = button.bounds
            dropOverlay.autoresizingMask = [.width, .height]
            dropOverlay.onDropURLs = { [weak self] urls in self?.handleDroppedURLs(urls) }
            dropOverlay.onDropTargetedChanged = { [weak self] isTargeted in
                self?.dropTargetedChanged(isTargeted)
            }
            dropOverlay.onClick = { [weak self] in self?.statusItemClicked() }
            button.addSubview(dropOverlay)
        }

        popup = PopupPanelController(
            content: MenuBarPopover(viewModel: viewModel, dismiss: { [weak self] in
                self?.popup?.dismiss()
            })
        ) { [weak self] in
            self?.statusItem.button?.highlight(false)
        }

        observeViewModel()
    }

    // MARK: - Popup

    private func statusItemClicked() {
        guard let popup else { return }
        if popup.isVisible || popup.wasJustDismissed {
            popup.dismiss()
            return
        }
        guard let anchor = buttonFrame else { return }
        popup.show(below: anchor)
        statusItem.button?.highlight(true)
    }

    private var buttonFrame: NSRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
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

        // Audio level must not be read here: it changes every frame and would re-run this whole pass through observation tracking.
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
            // Fast attack, slow decay: symmetric smoothing reads as flicker at 24fps.
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
