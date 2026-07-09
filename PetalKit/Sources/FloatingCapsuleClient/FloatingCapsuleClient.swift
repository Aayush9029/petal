import AppKit
import Dependencies
import DependenciesMacros
import UI
import Observation
import QuartzCore
import SwiftUI

@DependencyClient
public struct FloatingCapsuleClient: Sendable {
    public var showRecording: @Sendable (@escaping @Sendable () -> Void) async -> Void = { _ in }
    public var showTrimming: @Sendable () async -> Void = {}
    public var showSpeeding: @Sendable () async -> Void = {}
    public var updateLevel: @Sendable (Double) async -> Void = { _ in }
    public var showTranscribing: @Sendable () async -> Void = {}
    public var updateTranscriptionProgress: @Sendable (Double) async -> Void = { _ in }
    public var showRefining: @Sendable () async -> Void = {}
    public var showCancelConfirmation: @Sendable () async -> Void = {}
    public var showCopiedToClipboard: @Sendable () async -> Void = {}
    public var showAccessibilityPrompt: @Sendable (@escaping @Sendable () -> Void) async -> Void = { _ in }
    public var showAccessibilityEnabled: @Sendable () async -> Void = {}
    public var showError: @Sendable (String) async -> Void = { _ in }
    public var hide: @Sendable () async -> Void = {}
}

extension FloatingCapsuleClient: DependencyKey {
    public static var liveValue: Self {
        return Self(
            showRecording: { onTap in
                await MainActor.run { LiveFloatingCapsuleRuntimeContainer.shared.showRecording(onTap: onTap) }
            },
            showTrimming: {
                await MainActor.run { LiveFloatingCapsuleRuntimeContainer.shared.showTrimming() }
            },
            showSpeeding: {
                await MainActor.run { LiveFloatingCapsuleRuntimeContainer.shared.showSpeeding() }
            },
            updateLevel: { level in
                await MainActor.run { LiveFloatingCapsuleRuntimeContainer.shared.updateLevel(level) }
            },
            showTranscribing: {
                await MainActor.run { LiveFloatingCapsuleRuntimeContainer.shared.showTranscribing() }
            },
            updateTranscriptionProgress: { progress in
                await MainActor.run { LiveFloatingCapsuleRuntimeContainer.shared.updateTranscriptionProgress(progress) }
            },
            showRefining: {
                await MainActor.run { LiveFloatingCapsuleRuntimeContainer.shared.showRefining() }
            },
            showCancelConfirmation: {
                await MainActor.run { LiveFloatingCapsuleRuntimeContainer.shared.showCancelConfirmation() }
            },
            showCopiedToClipboard: {
                await MainActor.run { LiveFloatingCapsuleRuntimeContainer.shared.showCopiedToClipboard() }
            },
            showAccessibilityPrompt: { onTap in
                await MainActor.run { LiveFloatingCapsuleRuntimeContainer.shared.showAccessibilityPrompt(onTap: onTap) }
            },
            showAccessibilityEnabled: {
                await MainActor.run { LiveFloatingCapsuleRuntimeContainer.shared.showAccessibilityEnabled() }
            },
            showError: { message in
                await MainActor.run { LiveFloatingCapsuleRuntimeContainer.shared.showError(message) }
            },
            hide: {
                await MainActor.run { LiveFloatingCapsuleRuntimeContainer.shared.hide() }
            }
        )
    }
}

extension FloatingCapsuleClient: TestDependencyKey {
    public static var testValue: Self {
        Self(
            showRecording: { _ in },
            showTrimming: {},
            showSpeeding: {},
            updateLevel: { _ in },
            showTranscribing: {},
            updateTranscriptionProgress: { _ in },
            showRefining: {},
            showCancelConfirmation: {},
            showCopiedToClipboard: {},
            showAccessibilityPrompt: { _ in },
            showAccessibilityEnabled: {},
            showError: { _ in },
            hide: {}
        )
    }
}

public extension DependencyValues {
    var floatingCapsuleClient: FloatingCapsuleClient {
        get { self[FloatingCapsuleClient.self] }
        set { self[FloatingCapsuleClient.self] = newValue }
    }
}

@MainActor
private final class LiveFloatingCapsuleRuntime: NSObject {
    private let state = FloatingCapsuleState()
    private let panel: NSPanel
    private var preferredScreen: NSScreen?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var deferredScreenFollowTask: Task<Void, Never>?

    override init() {
        let contentView = FloatingCapsuleView(state: state)
        let hostingController = NSHostingController(rootView: contentView)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 52),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        panel.contentViewController = hostingController
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        self.panel = panel
        super.init()
        startFollowingActiveScreen()
    }

    func showRecording(onTap: @escaping @Sendable () -> Void) {
        state.cancelCountdownActive = false
        state.onAccessibilityTapped = nil
        state.onRecordingTapped = onTap
        state.phase = .recording
        showWindowIfNeeded()
    }

    func showTrimming() {
        state.onRecordingTapped = nil
        state.phase = .trimming
        showWindowIfNeeded()
    }

    func showSpeeding() {
        state.phase = .speeding
        showWindowIfNeeded()
    }

    func updateLevel(_ level: Double) {
        state.level = level
    }

    func showTranscribing() {
        state.transcriptionProgress = 0
        state.phase = .transcribing
        showWindowIfNeeded()
    }

    func showRefining() {
        state.phase = .refining
        showWindowIfNeeded()
    }

    func updateTranscriptionProgress(_ progress: Double) {
        let clamped = min(max(progress, 0), 1)
        state.transcriptionProgress = max(state.transcriptionProgress, clamped)
    }

    func showCancelConfirmation() {
        state.cancelCountdownActive = false
        state.phase = .confirmCancel
        showWindowIfNeeded()
        // Trigger on next run loop so SwiftUI sees the change from false → true
        DispatchQueue.main.async { [state] in
            state.cancelCountdownActive = true
        }
    }

    func showCopiedToClipboard() {
        state.phase = .copiedToClipboard
        showWindowIfNeeded()
    }

    func showAccessibilityPrompt(onTap: @escaping @Sendable () -> Void) {
        state.onRecordingTapped = nil
        state.onAccessibilityTapped = onTap
        state.phase = .accessibilityPrompt
        showWindowIfNeeded()
    }

    func showAccessibilityEnabled() {
        state.phase = .accessibilityEnabled
        showWindowIfNeeded()
    }

    func showError(_ message: String) {
        state.phase = .error(message)
        showWindowIfNeeded()
    }

    func hide() {
        state.phase = .hidden
        state.level = 0
        state.transcriptionProgress = 0
        state.cancelCountdownActive = false
        state.onRecordingTapped = nil
        state.onAccessibilityTapped = nil
        panel.orderOut(nil)
    }

    private func showWindowIfNeeded() {
        let screen = screenAtMouseLocation() ?? preferredScreen ?? NSScreen.main
        preferredScreen = screen
        positionPanel(on: screen)
        panel.orderFrontRegardless()
    }

    private func startFollowingActiveScreen() {
        let focusEvents: NSEvent.EventTypeMask = [
            .leftMouseDown,
            .leftMouseUp,
            .rightMouseDown,
            .rightMouseUp,
            .otherMouseDown,
            .otherMouseUp,
        ]
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: focusEvents) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.mouseFocusDidChange()
            }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: focusEvents) { [weak self] event in
            self?.mouseFocusDidChange()
            return event
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeApplicationDidChange),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    private func mouseFocusDidChange() {
        moveToScreenAtMouseLocation()

        deferredScreenFollowTask?.cancel()
        deferredScreenFollowTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            self?.moveToScreenAtMouseLocation()
        }
    }

    private func moveToScreenAtMouseLocation() {
        guard let screen = screenAtMouseLocation() else { return }
        preferredScreen = screen
        guard panel.isVisible else { return }
        positionPanel(on: screen)
    }

    @objc private func activeApplicationDidChange() {
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            let screen = self.screenAtMouseLocation() ?? NSScreen.main
            self.preferredScreen = screen
            guard self.panel.isVisible else { return }
            self.positionPanel(on: screen, animated: true)
        }
    }

    @objc private func activeSpaceDidChange() {
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            let screen = self.screenAtMouseLocation() ?? self.preferredScreen ?? NSScreen.main
            self.preferredScreen = screen
            guard self.panel.isVisible else { return }
            self.positionPanel(on: screen)
            self.panel.orderFrontRegardless()
        }
    }

    @objc private func screenConfigurationDidChange() {
        preferredScreen = screenAtMouseLocation() ?? NSScreen.main
        guard panel.isVisible else { return }
        positionPanel(on: preferredScreen)
    }

    private func screenAtMouseLocation() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouseLocation) }
    }

    private func positionPanel(on screen: NSScreen?, animated: Bool = false) {
        guard let screen else { return }
        let visibleFrame = screen.visibleFrame
        let x = visibleFrame.midX - panel.frame.width / 2
        let y = visibleFrame.minY + 36
        let origin = NSPoint(x: x, y: y)

        guard animated else {
            panel.setFrameOrigin(origin)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrameOrigin(origin)
        }
    }
}

@MainActor
private enum LiveFloatingCapsuleRuntimeContainer {
    static let shared = LiveFloatingCapsuleRuntime()
}
