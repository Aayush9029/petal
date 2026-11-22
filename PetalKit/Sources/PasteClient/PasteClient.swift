import AppKit
import Dependencies
import DependenciesMacros
import Foundation
import Sauce

public enum PasteResult: Equatable, Sendable {
    case pasted
    case copiedOnly
    case skipped

    public var rawValue: String {
        switch self {
        case .pasted: "pasted"
        case .copiedOnly: "copied_only"
        case .skipped: "skipped"
        }
    }
}

@DependencyClient
public struct PasteClient: Sendable {
    public var copy: @MainActor @Sendable (String) -> Void = { _ in }
    public var paste: @Sendable (_ text: String, _ restoreClipboard: Bool) async -> PasteResult = { _, _ in .copiedOnly }
    public var pressReturn: @Sendable () async -> Void = {}
}

extension PasteClient: DependencyKey {
    public static var liveValue: Self {
        return Self(
            copy: { text in _ = LivePasteRuntime.write(text, to: .general) },
            paste: { text, restoreClipboard in
                await LivePasteRuntime.shared.paste(text: text, restoreClipboard: restoreClipboard)
            },
            pressReturn: {
                await LivePasteRuntime.shared.pressReturn()
            }
        )
    }
}

extension PasteClient: TestDependencyKey {
    public static var testValue: Self {
        Self(
            copy: { _ in },
            paste: { _, _ in .pasted },
            pressReturn: {}
        )
    }
}

public extension DependencyValues {
    var pasteClient: PasteClient {
        get { self[PasteClient.self] }
        set { self[PasteClient.self] = newValue }
    }
}

@MainActor
private final class LivePasteRuntime {
    static let shared = LivePasteRuntime()

    private typealias PasteboardSnapshot = [[NSPasteboard.PasteboardType: Data]]

    private var pendingRestore: (changeCount: Int, snapshot: PasteboardSnapshot)?
    private var restoreTask: Task<Void, Never>?

    /// Electron apps such as VS Code read the clipboard some time after Command-V, so an early restore pastes the old content.
    private static let restoreDelay: Duration = .milliseconds(700)
    private static let modifierReleaseTimeout: Duration = .milliseconds(400)

    func paste(text: String, restoreClipboard: Bool) async -> PasteResult {
        let pasteboard = NSPasteboard.general

        let waitingSnapshot = pendingRestore.flatMap { $0.changeCount == pasteboard.changeCount ? $0.snapshot : nil }
        restoreTask?.cancel()
        restoreTask = nil
        pendingRestore = nil
        let snapshot = restoreClipboard ? waitingSnapshot ?? snapshotPasteboard(pasteboard) : nil

        guard Self.write(text, to: pasteboard) else { return .copiedOnly }
        await waitForModifierRelease()
        // Clipboard managers can rewrite the pasteboard during the wait.
        if pasteboard.string(forType: .string) != text, !Self.write(text, to: pasteboard) { return .copiedOnly }
        let transcriptChangeCount = pasteboard.changeCount
        if let snapshot { pendingRestore = (transcriptChangeCount, snapshot) }

        guard !Task.isCancelled, postCommandV() else {
            if pendingRestore?.changeCount == transcriptChangeCount { pendingRestore = nil }
            return .copiedOnly
        }

        if let snapshot {
            restoreTask = Task { [weak self] in
                do { try await Task.sleep(for: Self.restoreDelay) } catch { return }
                guard let self, self.pendingRestore?.changeCount == transcriptChangeCount else { return }
                self.pendingRestore = nil
                self.restoreTask = nil
                guard pasteboard.changeCount == transcriptChangeCount else { return }
                self.restorePasteboard(pasteboard, snapshot: snapshot)
            }
        }

        return .pasted
    }

    static func write(_ text: String, to pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    /// A held shortcut key, such as Option or Control, turns Command-V into a different shortcut in the front app.
    private func waitForModifierRelease() async {
        let held: CGEventFlags = [.maskAlternate, .maskControl, .maskShift, .maskCommand, .maskSecondaryFn]
        let deadline = ContinuousClock.now + Self.modifierReleaseTimeout
        while !CGEventSource.flagsState(.hidSystemState).isDisjoint(with: held), ContinuousClock.now < deadline {
            do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
        }
    }

    func pressReturn() {
        guard AXIsProcessTrusted(), let source = CGEventSource(stateID: .hidSystemState) else { return }
        let returnKey = Sauce.shared.keyCode(for: .return)
        CGEvent(keyboardEventSource: source, virtualKey: returnKey, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: source, virtualKey: returnKey, keyDown: false)?.post(tap: .cghidEventTap)
    }

    private func postCommandV() -> Bool {
        guard AXIsProcessTrusted() else {
            return false
        }

        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            return false
        }
        // Keys that the user presses at the same moment must not mix with the shortcut.
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        let vKey: CGKeyCode = Sauce.shared.keyCode(for: .v)

        guard
            let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
            let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        else {
            return false
        }

        vDown.flags = .maskCommand
        vUp.flags = .maskCommand

        vDown.post(tap: .cgSessionEventTap)
        vUp.post(tap: .cgSessionEventTap)

        return true
    }

    private func snapshotPasteboard(_ pasteboard: NSPasteboard) -> PasteboardSnapshot {
        (pasteboard.pasteboardItems ?? []).map { item in
            var entry: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    entry[type] = data
                }
            }
            return entry
        }
    }

    private func restorePasteboard(_ pasteboard: NSPasteboard, snapshot: PasteboardSnapshot) {
        pasteboard.clearContents()

        guard !snapshot.isEmpty else {
            return
        }

        let items = snapshot.map { entry -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entry {
                item.setData(data, forType: type)
            }
            return item
        }

        pasteboard.writeObjects(items)
    }
}
