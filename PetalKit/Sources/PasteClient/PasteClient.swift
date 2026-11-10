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
    public var paste: @Sendable (_ text: String, _ restoreClipboard: Bool) async -> PasteResult = { _, _ in .copiedOnly }
    /// Presses Return in the front app, which sends the message in chat apps and runs the command in terminals.
    public var pressReturn: @Sendable () async -> Void = {}
}

extension PasteClient: DependencyKey {
    public static var liveValue: Self {
        return Self(
            paste: { text, restoreClipboard in
                await LivePasteRuntimeContainer.shared.paste(text: text, restoreClipboard: restoreClipboard)
            },
            pressReturn: {
                await LivePasteRuntimeContainer.shared.pressReturn()
            }
        )
    }
}

extension PasteClient: TestDependencyKey {
    public static var testValue: Self {
        Self(
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
    private typealias PasteboardSnapshot = [[NSPasteboard.PasteboardType: Data]]

    private var pendingRestore: (task: Task<Void, Never>, snapshot: PasteboardSnapshot)?

    /// Electron apps such as VS Code read the clipboard some time after Command-V, so an early restore pastes the old content.
    private static let restoreDelay: Duration = .milliseconds(700)
    private static let modifierReleaseTimeout: Duration = .milliseconds(400)

    func paste(text: String, restoreClipboard: Bool) async -> PasteResult {
        let pasteboard = NSPasteboard.general

        // A restore that still waits holds the real clipboard content. The clipboard now holds the last transcript.
        let waitingSnapshot = pendingRestore?.snapshot
        pendingRestore?.task.cancel()
        pendingRestore = nil
        let snapshot = restoreClipboard ? waitingSnapshot ?? snapshotPasteboard(pasteboard) : nil

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            return .copiedOnly
        }
        let transcriptChangeCount = pasteboard.changeCount

        await waitForModifierRelease()
        guard postCommandV() else {
            return .copiedOnly
        }

        if let snapshot {
            let task = Task { [weak self] in
                try? await Task.sleep(for: Self.restoreDelay)
                guard !Task.isCancelled, let self else { return }
                self.pendingRestore = nil
                // A different change count means the user copied something new, and that content stays.
                guard pasteboard.changeCount == transcriptChangeCount else { return }
                self.restorePasteboard(pasteboard, snapshot: snapshot)
            }
            pendingRestore = (task, snapshot)
        }

        return .pasted
    }

    /// A held shortcut key, such as Option or Control, turns Command-V into a different shortcut in the front app.
    private func waitForModifierRelease() async {
        let held: CGEventFlags = [.maskAlternate, .maskControl, .maskShift, .maskCommand, .maskSecondaryFn]
        let deadline = ContinuousClock.now + Self.modifierReleaseTimeout
        while !CGEventSource.flagsState(.hidSystemState).isDisjoint(with: held), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
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

@MainActor
private enum LivePasteRuntimeContainer {
    static let shared = LivePasteRuntime()
}
