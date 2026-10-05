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

    func paste(text: String, restoreClipboard: Bool) async -> PasteResult {
        let pasteboard = NSPasteboard.general
        let snapshot = restoreClipboard ? snapshotPasteboard(pasteboard) : nil

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            return .copiedOnly
        }

        guard postCommandV() else {
            return .copiedOnly
        }

        if let snapshot {
            try? await Task.sleep(for: .milliseconds(180))
            restorePasteboard(pasteboard, snapshot: snapshot)
        }

        return .pasted
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

        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return false
        }

        let commandKey: CGKeyCode = 0x37
        let vKey: CGKeyCode = Sauce.shared.keyCode(for: .v)

        guard
            let commandDown = CGEvent(keyboardEventSource: source, virtualKey: commandKey, keyDown: true),
            let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
            let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false),
            let commandUp = CGEvent(keyboardEventSource: source, virtualKey: commandKey, keyDown: false)
        else {
            return false
        }

        commandDown.flags = .maskCommand
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand

        commandDown.post(tap: .cghidEventTap)
        vDown.post(tap: .cghidEventTap)
        vUp.post(tap: .cghidEventTap)
        commandUp.post(tap: .cghidEventTap)

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
