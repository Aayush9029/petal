import AppKit

@MainActor
final class AccessibilityGuideContentView: NSView {
    private let onClose: () -> Void

    init(application: AccessibilityGuideApplication, onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init(frame: .zero)
        setUp(application: application)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUp(application: AccessibilityGuideApplication) {
        let arrowView = NSImageView()
        arrowView.translatesAutoresizingMaskIntoConstraints = false
        arrowView.image = NSImage(
            systemSymbolName: "arrow.up.circle.fill",
            accessibilityDescription: nil
        )
        arrowView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
        arrowView.contentTintColor = .controlAccentColor
        arrowView.setAccessibilityHidden(true)

        let titleLabel = NSTextField(labelWithString: "Add \(application.displayName) to Accessibility")
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail

        let subtitleLabel = NSTextField(
            labelWithString: "Drag the app below into the list above, then turn it on."
        )
        subtitleLabel.font = .systemFont(ofSize: 12.5, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail

        let labelStack = NSStackView(views: [titleLabel, subtitleLabel])
        labelStack.translatesAutoresizingMaskIntoConstraints = false
        labelStack.orientation = .vertical
        labelStack.alignment = .leading
        labelStack.spacing = 3

        let closeButton = NSButton(
            image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close") ?? NSImage(),
            target: self,
            action: #selector(closeButtonPressed)
        )
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.isBordered = false
        closeButton.imagePosition = .imageOnly
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.toolTip = "Close accessibility guide"
        closeButton.setAccessibilityLabel("Close accessibility guide")

        let dragView = AccessibilityAppDragView(application: application)
        dragView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(arrowView)
        addSubview(labelStack)
        addSubview(closeButton)
        addSubview(dragView)

        NSLayoutConstraint.activate([
            arrowView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            arrowView.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            arrowView.widthAnchor.constraint(equalToConstant: 30),
            arrowView.heightAnchor.constraint(equalToConstant: 30),

            labelStack.leadingAnchor.constraint(equalTo: arrowView.trailingAnchor, constant: 12),
            labelStack.centerYAnchor.constraint(equalTo: arrowView.centerYAnchor),
            labelStack.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -12),

            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            closeButton.widthAnchor.constraint(equalToConstant: 28),
            closeButton.heightAnchor.constraint(equalToConstant: 28),

            dragView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            dragView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            dragView.topAnchor.constraint(equalTo: topAnchor, constant: 72),
            dragView.heightAnchor.constraint(equalToConstant: 54),
        ])
    }

    @objc
    private func closeButtonPressed() {
        onClose()
    }
}
