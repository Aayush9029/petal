import AppKit

@MainActor
final class AccessibilityAppDragView: NSView, NSPasteboardItemDataProvider, NSDraggingSource {
    private let application: AccessibilityGuideApplication
    private let contentView = NSView()
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    init(application: AccessibilityGuideApplication) {
        self.application = application
        super.init(frame: .zero)
        setUp()
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .openHand)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
            owner: self
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setDataProvider(self, forTypes: [.fileURL])

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        draggingItem.setDraggingFrame(bounds, contents: draggingImage())

        let session = beginDraggingSession(with: [draggingItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func pasteboard(
        _ pasteboard: NSPasteboard?,
        item: NSPasteboardItem,
        provideDataForType type: NSPasteboard.PasteboardType
    ) {
        guard type == .fileURL else { return }
        item.setData(application.bundleURL.dataRepresentation, forType: .fileURL)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        NSCursor.closedHand.set()
        contentView.isHidden = true
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        NSCursor.openHand.set()
        contentView.isHidden = false
    }

    private func setUp() {
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.75

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("\(application.displayName) application")
        setAccessibilityHelp("Drag this application into the Accessibility list above")

        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)

        let iconView = NSImageView(image: application.icon)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.setAccessibilityHidden(true)

        let titleLabel = NSTextField(labelWithString: application.displayName)
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail

        let pathLabel = NSTextField(labelWithString: application.bundleURL.lastPathComponent)
        pathLabel.font = .systemFont(ofSize: 11, weight: .regular)
        pathLabel.textColor = .tertiaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle

        let labelStack = NSStackView(views: [titleLabel, pathLabel])
        labelStack.translatesAutoresizingMaskIntoConstraints = false
        labelStack.orientation = .vertical
        labelStack.alignment = .leading
        labelStack.spacing = 1

        let dragLabel = NSTextField(labelWithString: "Drag")
        dragLabel.font = .systemFont(ofSize: 12, weight: .medium)
        dragLabel.textColor = .secondaryLabelColor
        dragLabel.translatesAutoresizingMaskIntoConstraints = false

        let dragIcon = NSImageView()
        dragIcon.translatesAutoresizingMaskIntoConstraints = false
        dragIcon.image = NSImage(
            systemSymbolName: "hand.draw",
            accessibilityDescription: nil
        )
        dragIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        dragIcon.contentTintColor = .secondaryLabelColor
        dragIcon.setAccessibilityHidden(true)

        let dragHintStack = NSStackView(views: [dragLabel, dragIcon])
        dragHintStack.translatesAutoresizingMaskIntoConstraints = false
        dragHintStack.orientation = .horizontal
        dragHintStack.alignment = .centerY
        dragHintStack.spacing = 6

        contentView.addSubview(iconView)
        contentView.addSubview(labelStack)
        contentView.addSubview(dragHintStack)

        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),

            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 34),
            iconView.heightAnchor.constraint(equalToConstant: 34),

            labelStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 11),
            labelStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            labelStack.trailingAnchor.constraint(lessThanOrEqualTo: dragHintStack.leadingAnchor, constant: -12),

            dragHintStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            dragHintStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            dragIcon.widthAnchor.constraint(equalToConstant: 18),
            dragIcon.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    private func updateAppearance() {
        guard let layer else { return }
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        if isDark {
            layer.backgroundColor = NSColor.white.withAlphaComponent(isHovered ? 0.13 : 0.08).cgColor
            layer.borderColor = NSColor.white.withAlphaComponent(isHovered ? 0.20 : 0.12).cgColor
        } else {
            layer.backgroundColor = NSColor.white.withAlphaComponent(isHovered ? 0.72 : 0.54).cgColor
            layer.borderColor = NSColor.black.withAlphaComponent(isHovered ? 0.13 : 0.08).cgColor
        }
    }

    private func draggingImage() -> NSImage {
        guard let representation = bitmapImageRepForCachingDisplay(in: bounds) else {
            return application.icon
        }

        cacheDisplay(in: bounds, to: representation)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(representation)
        return image
    }
}
