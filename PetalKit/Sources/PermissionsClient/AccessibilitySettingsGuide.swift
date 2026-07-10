@preconcurrency import ApplicationServices
import AppKit
import Foundation

@MainActor
final class AccessibilitySettingsGuide {
    static let shared = AccessibilitySettingsGuide()

    private let refreshInterval: TimeInterval = 0.15
    private var windowController: AccessibilityGuideWindowController?
    private var trackingTimer: Timer?
    private var activationObserver: NSObjectProtocol?
    private var hasPresentedWindow = false

    private init() {}

    func present() {
        dismiss()

        windowController = AccessibilityGuideWindowController(
            application: .current(),
            onClose: { [weak self] in self?.dismiss() }
        )
        hasPresentedWindow = false

        guard let settingsURL = URL(
            string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
        ) else {
            return
        }

        NSWorkspace.shared.open(settingsURL)
        startTrackingSettingsWindow()
    }

    func dismiss() {
        trackingTimer?.invalidate()
        trackingTimer = nil

        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }

        windowController?.close()
        windowController = nil
        hasPresentedWindow = false
    }

    private func startTrackingSettingsWindow() {
        let timer = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshWindowPosition()
            }
        }
        trackingTimer = timer
        RunLoop.main.add(timer, forMode: .common)

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshWindowPosition()
            }
        }

        refreshWindowPosition()
    }

    private func refreshWindowPosition() {
        if AXIsProcessTrusted() {
            dismiss()
            return
        }

        guard let snapshot = AccessibilitySettingsWindowLocator.frontmostWindow()
            ?? AccessibilitySettingsWindowLocator.fallbackWindow() else {
            windowController?.hide()
            return
        }

        if hasPresentedWindow {
            windowController?.updatePosition(
                settingsFrame: snapshot.frame,
                visibleFrame: snapshot.visibleFrame
            )
        } else {
            windowController?.present(
                settingsFrame: snapshot.frame,
                visibleFrame: snapshot.visibleFrame
            )
            hasPresentedWindow = true
        }
    }
}
