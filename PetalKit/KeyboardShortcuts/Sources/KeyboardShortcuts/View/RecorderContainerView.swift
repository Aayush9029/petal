#if os(macOS)

import AppKit
import Carbon.HIToolbox

protocol RecorderContainerDelegate: AnyObject {
    func recorderModeDidChange(_ mode: KeyboardShortcuts.RecorderMode)
}

final class RecorderContainerView: NSView {
    private let onChange: ((_ shortcut: KeyboardShortcuts.Shortcut?) -> Void)?
    private var oldSet: String?
    private var mode: KeyboardShortcuts.RecorderMode = .ready {
        willSet {
            if case let .set(string) = mode, case .preRecording = newValue {
                oldSet = string
            } else if case .set = newValue {
                oldSet = nil
            }
        }
        didSet {
            // the delegate method will trigger UI update
            DispatchQueue.main.async {
                self.delegate?.recorderModeDidChange(self.mode)
            }
        }
    }

    var delegate: RecorderContainerDelegate?
    private var shortcutsNameChangeObserver: NSObjectProtocol?
    private var windowDidResignKeyObserver: NSObjectProtocol?

    /**
     The shortcut name for the recorder.

     Can be dynamically changed at any time.
     */
    var shortcutName: KeyboardShortcuts.Name {
        didSet {
            guard shortcutName != oldValue else {
                return
            }

            setStringValue(name: shortcutName)
        }
    }

    /// :nodoc:
    override var canBecomeKeyView: Bool { mode.isActive }

    required init(
        for name: KeyboardShortcuts.Name,
        onChange: ((_ shortcut: KeyboardShortcuts.Shortcut?) -> Void)? = nil
    ) {
        self.shortcutName = name
        self.onChange = onChange

        super.init(frame: .zero)

        self.wantsLayer = true
        setContentHuggingPriority(.defaultHigh, for: .vertical)
        setContentHuggingPriority(.defaultHigh, for: .horizontal)

        setUpEvents()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func startRecording() {
        guard !mode.isActive else { return }
        mode = .preRecording
        focus()
    }

    func stopRecording() {
        if let oldSet {
            mode = .set(oldSet)
        } else if case .preRecording = mode {
            mode = .ready
        } else if case .recording = mode {
            mode = .ready
        }
    }

    private func setStringValue(name: KeyboardShortcuts.Name) {
        if let shortcut = KeyboardShortcuts.getShortcut(for: name).map({ "\($0)" }) {
            mode = .set(shortcut)
        } else {
            oldSet = nil
            mode = .ready
        }
    }

    private func setUpEvents() {
        shortcutsNameChangeObserver = NotificationCenter.default.addObserver(forName: .shortcutByNameDidChange, object: nil, queue: nil) { [weak self] notification in
            guard
                let self,
                let nameInNotification = notification.userInfo?["name"] as? KeyboardShortcuts.Name,
                nameInNotification == self.shortcutName
            else {
                return
            }
            
            self.setStringValue(name: nameInNotification)
        }
    }

    /// :nodoc:
    override func viewDidMoveToWindow() {
        guard let window else {
            windowDidResignKeyObserver = nil
            endRecording(.ready)
            return
        }

        setStringValue(name: shortcutName) // set here, not in the init so the property observer will be called

        // Ensures the recorder stops when the window is hidden.
        // This is especially important for Settings windows, which as of macOS 13.5,
        // only hides instead of closes when you click the close button.
        windowDidResignKeyObserver = NotificationCenter.default
            .addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: nil
            ) { [weak self] _ in
                guard
                    let self,
                    let window = self.window
                else {
                    return
                }
                self.endRecording {
                    if case .preRecording = self.mode {
                        return .ready
                    } else if case .recording = self.mode {
                        return .ready
                    } else {
                        return self.mode
                    }
                }

                window.makeFirstResponder(nil)
            }
    }

    override func becomeFirstResponder() -> Bool {
        let shouldBecomeFirstResponder = super.becomeFirstResponder()

        guard shouldBecomeFirstResponder else {
            return shouldBecomeFirstResponder
        }

        KeyboardShortcuts.isPaused = true
        return shouldBecomeFirstResponder
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }

    // in this method the event won't have modifiers, only the character
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard mode.isActive else { return false }
        guard !onlyTabPressed(event) else {
            endRecording(.ready)
            return true
        }

        guard !onlyEscapePressed(event) else {
            endRecording {
                if let oldSet {
                    return .set(oldSet)
                } else {
                    return .ready
                }
            }

            return true
        }

        guard !onlyDeletePressed(event) else {
            saveShortcut(nil)
            return true
        }

        guard !shiftOrFnIsTheOnlyModifier(event) else {
            mode = .preRecording
            return false
        }

        guard !event.modifiers.isEmpty, let shortcut = KeyboardShortcuts.Shortcut(event: event) else {
            endRecording(.ready)
            return false
        }

        if let menuItem = shortcut.takenByMainMenu {
            endRecording(.ready)

            NSAlert.showModal(
                for: self.window,
                title: String.localizedStringWithFormat("keyboard_shortcut_used_by_menu_item".localized, menuItem.title)
            )
            return true
        }

        if shortcut.isTakenBySystem {
            endRecording(.ready)

            NSAlert.showModal(
                for: self.window,
                title: "keyboard_shortcut_used_by_system".localized,
                // TODO: Add button to offer to open the relevant system settings pane for the user.
                message: "keyboard_shortcuts_can_be_changed".localized,
                buttonTitles: [
                    "ok".localized,
                    "force_use_shortcut".localized
                ]
            )
            return true
        }

        saveShortcut(shortcut)
        return true
    }

    override func flagsChanged(with event: NSEvent) {
        guard mode.isActive else { return }
        if event.modifiers.isEmpty {
            mode = .preRecording
        } else {
            mode = .recording(event.modifiers.description)
            if let shortcut = shortcutFromModifierEvent(event) {
                saveShortcut(shortcut)
            }
        }
    }

    private func onlyEscapePressed(_ event: NSEvent) -> Bool {
        event.modifiers.isEmpty && event.keyCode == kVK_Escape
    }

    private func onlyTabPressed(_ event: NSEvent) -> Bool {
        event.modifiers.isEmpty && event.specialKey == .tab
    }

    /// The “shift” key is not allowed without other modifiers or a function key, since it doesn't actually work.
    private func shiftOrFnIsTheOnlyModifier(_ event: NSEvent) -> Bool {
        event.modifiers.subtracting(.shift).isEmpty || event.specialKey?.isFunctionKey == true
    }

    private func onlyDeletePressed(_ event: NSEvent) -> Bool {
        event.modifiers.isEmpty && (
            event.specialKey == .delete
                || event.specialKey == .deleteForward
                || event.specialKey == .backspace
        )
    }

    private func shortcutFromModifierEvent(_ event: NSEvent) -> KeyboardShortcuts.Shortcut? {
        let key = KeyboardShortcuts.Key(rawValue: Int(event.keyCode))
        guard
            let modifierKey = key.modifierFlag
        else {
            return nil
        }

        // Record only on key-up so modifier + letter/number shortcuts can still be entered.
        guard !event.modifiers.contains(modifierKey) else {
            return nil
        }

        let remainingModifiers = event.modifiers.subtracting(modifierKey)
        guard !remainingModifiers.isEmpty else {
            return nil
        }

        return KeyboardShortcuts.Shortcut(
            carbonKeyCode: key.rawValue,
            carbonModifiers: remainingModifiers.carbon
        )
    }

    private func saveShortcut(_ shortcut: KeyboardShortcuts.Shortcut?) {
        endRecording {
            if let shortcut {
                return .set(shortcut.description)
            } else {
                self.oldSet = nil
                return .ready
            }
        }

        KeyboardShortcuts.setShortcut(shortcut, for: shortcutName)
        onChange?(shortcut)
    }

    private func endRecording(_ newMode: () -> KeyboardShortcuts.RecorderMode) {
        endRecording(newMode())
    }

    private func endRecording(_ newMode: KeyboardShortcuts.RecorderMode) {
        KeyboardShortcuts.isPaused = false
        blur()
        self.mode = newMode
    }

    deinit {
        NotificationCenter.default.removeObserver(shortcutsNameChangeObserver as Any)
        NotificationCenter.default.removeObserver(windowDidResignKeyObserver as Any)
    }
}

private extension KeyboardShortcuts.Key {
    var modifierFlag: NSEvent.ModifierFlags? {
        if self == .command || self == .rightCommand {
            return .command
        }

        if self == .option || self == .rightOption {
            return .option
        }

        if self == .control || self == .rightControl {
            return .control
        }

        if self == .shift || self == .rightShift {
            return .shift
        }

        return nil
    }
}

#endif
