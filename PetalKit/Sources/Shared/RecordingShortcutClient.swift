import AppKit
import Dependencies
import DependenciesMacros
import KeyboardShortcuts
import Sharing

@DependencyClient
public struct RecordingShortcutClient: Sendable {
    public var current: @MainActor @Sendable () -> RecordedShortcut = { .unconfigured }
    public var record: @MainActor @Sendable (RecordedShortcut) -> Void
    public var resolvePasteConflict: @MainActor @Sendable () -> Void
}

extension RecordingShortcutClient: DependencyKey {
    public static let liveValue = Self(
        current: {
            @SharedReader(.shortcutTriggerMode) var mode
            switch mode {
            case .combo:
                guard let combo = KeyboardShortcuts.getShortcut(for: .pushToTalk) else { return .unconfigured }
                var names: [String] = []
                if combo.modifiers.contains(.control) { names.append("⌃") }
                if combo.modifiers.contains(.option) { names.append("⌥") }
                if combo.modifiers.contains(.command) { names.append("⌘") }
                names.append(combo.keyToCharacter()?.capitalized ?? "Key \(combo.carbonKeyCode)")
                return .combo(keyCode: combo.carbonKeyCode, carbonModifiers: combo.carbonModifiers, displayNames: names)

            case .doubleTap:
                @SharedReader(.doubleTapKey) var key
                guard key.isConfigured else { return .unconfigured }
                return .singleKey(keyCode: key.keyCode, isModifier: key.isModifier, displayName: key.displayName)
            }
        },
        record: { shortcut in
            @Shared(.shortcutTriggerMode) var mode
            @Shared(.doubleTapKey) var key
            switch shortcut {
            case .unconfigured:
                KeyboardShortcuts.setShortcut(nil, for: .pushToTalk)
                $key.withLock { $0 = .unconfigured }
            case let .singleKey(keyCode, isModifier, _):
                @Shared(.doubleTapInterval) var interval
                $mode.withLock { $0 = .doubleTap }
                $key.withLock { $0 = DoubleTapKey(keyCode: keyCode, isModifier: isModifier) }
                $interval.withLock { $0 = 0.4 }
                KeyboardShortcuts.setShortcut(nil, for: .pushToTalk)
            case let .combo(keyCode, modifiers, _):
                $mode.withLock { $0 = .combo }
                KeyboardShortcuts.setShortcut(.init(carbonKeyCode: keyCode, carbonModifiers: modifiers), for: .pushToTalk)
                $key.withLock { $0 = .unconfigured }
            }
        },
        resolvePasteConflict: {
            guard let combo = KeyboardShortcuts.getShortcut(for: .pushToTalk),
                  combo == KeyboardShortcuts.getShortcut(for: .pasteLastTranscription)
            else { return }
            KeyboardShortcuts.setShortcut(nil, for: .pasteLastTranscription)
            NSSound.beep()
        }
    )

    public static let testValue = Self()
}

public extension DependencyValues {
    var recordingShortcut: RecordingShortcutClient {
        get { self[RecordingShortcutClient.self] }
        set { self[RecordingShortcutClient.self] = newValue }
    }
}
