#if os(macOS)

import AppKit
import Carbon.HIToolbox
import SwiftUI

// MARK: - RecordedShortcut

public enum RecordedShortcut: Hashable, Sendable {
    case unconfigured
    case singleKey(keyCode: Int, isModifier: Bool, displayName: String)
    case combo(keyCode: Int, carbonModifiers: Int, displayNames: [String])

    public var isConfigured: Bool {
        if case .unconfigured = self { return false }
        return true
    }

    public var displayNames: [String] {
        switch self {
        case .unconfigured: []
        case let .singleKey(_, _, name): [name]
        case let .combo(_, _, names): names
        }
    }
}

// MARK: - UnifiedShortcutRecorder

public struct UnifiedShortcutRecorder: View {
    @Binding var shortcut: RecordedShortcut
    @Namespace private var namespace

    @State private var mode: Mode = .ready
    @State private var symbolName = "xmark.circle.fill"
    @State private var delayedResetTask: Task<Void, Never>?

    private enum Mode: Equatable {
        case ready
        case recording
        case set([String])

        var isRecording: Bool {
            if case .recording = self { return true }
            return false
        }

        var isSet: Bool {
            if case .set = self { return true }
            return false
        }

        var thereIsNoKeys: Bool {
            switch self {
            case .ready, .recording: return true
            case .set: return false
            }
        }
    }

    public init(shortcut: Binding<RecordedShortcut>) {
        self._shortcut = shortcut
    }

    public var body: some View {
        ZStack {
            _UnifiedRecorderView(
                isActive: mode.isRecording,
                onKeyRecorded: { keyCode, isModifier, displayName in
                    shortcut = .singleKey(keyCode: keyCode, isModifier: isModifier, displayName: displayName)
                    setRecorded([displayName])
                },
                onComboRecorded: { keyCode, carbonModifiers, displayNames in
                    shortcut = .combo(keyCode: keyCode, carbonModifiers: carbonModifiers, displayNames: displayNames)
                    setRecorded(displayNames)
                },
                onCancelled: {
                    withAnimation(.spring(duration: 0.4)) {
                        mode = shortcut.isConfigured ? .set(shortcut.displayNames) : .ready
                    }
                }
            )
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)

            HStack {
                Button(action: activateRecorder) {
                    ZStack {
                        switch mode {
                        case .ready:
                            Text("RECORD")
                                .commandStyle()
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .trailing).combined(with: .opacity)
                                ))
                        case .recording:
                            HStack {
                                BlinkingLight()
                                Text("PRESS A KEY OR COMBO")
                                    .commandStyle()
                                    .foregroundStyle(Color.secondary)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            .padding(.horizontal, 8)
                            .transition(.asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))

                        case let .set(displayNames):
                            HStack(spacing: 2) {
                                ForEach(Array(displayNames.enumerated()), id: \.offset) { _, symbol in
                                    ShortcutSymbol(symbol: symbol)
                                        .transition(.move(edge: .leading).combined(with: .opacity))
                                }
                            }
                            .transition(.offset(x: -30).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, mode.thereIsNoKeys ? 8 : 2)
                    .frame(height: 26)
                    .visualEffect(.adaptive(.windowBackground))
                    .clipShape(RoundedRectangle(cornerRadius: mode.thereIsNoKeys ? 13 : 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: mode.thereIsNoKeys ? 13 : 6, style: .continuous).stroke(.secondary, lineWidth: 0.5).opacity(0.3))
                    .contentShape(RoundedRectangle(cornerRadius: mode.thereIsNoKeys ? 13 : 6, style: .continuous))
                }
                .buttonStyle(.plain)

                if mode != .ready {
                    Button(
                        action: {
                            if mode.isRecording {
                                withAnimation(.spring(duration: 0.4)) {
                                    mode = shortcut.isConfigured ? .set(shortcut.displayNames) : .ready
                                }
                            } else if mode.isSet {
                                shortcut = .unconfigured
                                withAnimation(.spring(duration: 0.4)) {
                                    mode = .ready
                                }
                            }
                        },
                        label: {
                            Image(systemName: symbolName)
                                .fontWeight(.bold)
                                .imageScale(.large)
                                .foregroundColor(Color.secondary)
                        }
                    )
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity).combined(with: .offset(x: -30)))
                }
            }
        }
        .animation(.spring(duration: 0.4), value: mode)
        .onAppear {
            if shortcut.isConfigured {
                mode = .set(shortcut.displayNames)
            }
        }
    }

    private func activateRecorder() {
        guard !mode.isRecording else { return }
        delayedResetTask?.cancel()
        symbolName = "xmark.circle.fill"
        withAnimation(.spring(duration: 0.4)) {
            mode = .recording
        }
    }

    private func setRecorded(_ displayNames: [String]) {
        withAnimation(.spring(duration: 0.4)) {
            mode = .set(displayNames)
            symbolName = "checkmark.circle.fill"
        }
        delayedResetTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.default) {
                symbolName = "xmark.circle.fill"
            }
        }
    }
}

// MARK: - NSViewRepresentable for key capture

private struct _UnifiedRecorderView: NSViewRepresentable {
    let isActive: Bool
    let onKeyRecorded: (Int, Bool, String) -> Void
    let onComboRecorded: (Int, Int, [String]) -> Void
    let onCancelled: () -> Void

    func makeNSView(context: Context) -> _UnifiedNSView {
        let view = _UnifiedNSView()
        view.onKeyRecorded = onKeyRecorded
        view.onComboRecorded = onComboRecorded
        view.onCancelled = onCancelled
        return view
    }

    func updateNSView(_ nsView: _UnifiedNSView, context: Context) {
        nsView.onKeyRecorded = onKeyRecorded
        nsView.onComboRecorded = onComboRecorded
        nsView.onCancelled = onCancelled
        if isActive {
            nsView.startRecording()
        } else {
            nsView.stopRecording()
        }
    }
}

final class _UnifiedNSView: NSView {
    var onKeyRecorded: ((Int, Bool, String) -> Void)?
    var onComboRecorded: ((Int, Int, [String]) -> Void)?
    var onCancelled: (() -> Void)?
    private var isRecording = false
    private var pendingModifierKeyCode: Int?
    private var localMonitor: Any?

    override var canBecomeKeyView: Bool { isRecording }
    override var acceptsFirstResponder: Bool { isRecording }

    func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        pendingModifierKeyCode = nil
        KeyboardShortcuts.isPaused = true
        window?.makeFirstResponder(self)
        installMonitors()
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        pendingModifierKeyCode = nil
        KeyboardShortcuts.isPaused = false
        removeMonitors()
    }

    private func installMonitors() {
        removeMonitors()

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.isRecording else { return event }

            if event.type == .flagsChanged {
                self.handleFlagsChanged(event)
                return nil
            }

            self.handleKeyDown(event)
            return nil
        }
    }

    private func removeMonitors() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        pendingModifierKeyCode = nil
        let keyCode = Int(event.keyCode)

        // Tab cancels (focus navigation)
        if event.keyCode == UInt16(kVK_Tab) {
            stopRecording()
            onCancelled?()
            return
        }

        // Escape cancels recording
        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            onCancelled?()
            return
        }

        // Delete/Backspace clears the key
        if event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete) {
            stopRecording()
            onCancelled?()
            return
        }

        // Check for meaningful modifiers (command, option, control)
        let significantModifiers = event.modifierFlags.intersection([.command, .option, .control])
        if !significantModifiers.isEmpty {
            // Combo: modifier + key
            let carbonMods = significantModifiers.carbon
            var displayNames = modifierDisplayNames(for: significantModifiers)
            let keyName = regularKeyDisplayName(keyCode: keyCode, event: event)
            displayNames.append(keyName)
            stopRecording()
            onComboRecorded?(keyCode, carbonMods, displayNames)
        } else {
            // Single key, no modifiers
            let displayName = regularKeyDisplayName(keyCode: keyCode, event: event)
            stopRecording()
            onKeyRecorded?(keyCode, false, displayName)
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let keyCode = Int(event.keyCode)
        let isModifierKey = Self.modifierKeyCodes.contains(keyCode)
        guard isModifierKey else { return }

        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) != [] {
            // Modifier pressed down
            pendingModifierKeyCode = keyCode
        } else if let pending = pendingModifierKeyCode, pending == keyCode {
            // Modifier released — this is the key (single modifier double-tap)
            pendingModifierKeyCode = nil
            let displayName = Self.modifierDisplayName(for: keyCode)
            stopRecording()
            onKeyRecorded?(keyCode, true, displayName)
        }
    }

    private func regularKeyDisplayName(keyCode: Int, event: NSEvent) -> String {
        // Map special keys to their symbolic representations
        if let special = Self.specialKeyDisplayName(for: keyCode) {
            return special
        }
        if let chars = event.charactersIgnoringModifiers, !chars.trimmingCharacters(in: .whitespaces).isEmpty {
            return chars.uppercased()
        }
        return "Key \(keyCode)"
    }

    private static func specialKeyDisplayName(for keyCode: Int) -> String? {
        switch keyCode {
        case kVK_Space:         return "\u{2423}"  // ␣
        case kVK_Return:        return "\u{21A9}"  // ↩
        case kVK_Escape:        return "\u{238B}"  // ⎋
        case kVK_Delete:        return "\u{232B}"  // ⌫
        case kVK_ForwardDelete: return "\u{2326}"  // ⌦
        case kVK_UpArrow:       return "\u{2191}"  // ↑
        case kVK_DownArrow:     return "\u{2193}"  // ↓
        case kVK_LeftArrow:     return "\u{2190}"  // ←
        case kVK_RightArrow:    return "\u{2192}"  // →
        case kVK_Tab:           return "\u{21E5}"  // ⇥
        case kVK_CapsLock:      return "\u{21EA}"  // ⇪
        default:                return nil
        }
    }

    private func modifierDisplayNames(for flags: NSEvent.ModifierFlags) -> [String] {
        var names = [String]()
        if flags.contains(.control) { names.append("\u{2303}") }
        if flags.contains(.option) { names.append("\u{2325}") }
        if flags.contains(.command) { names.append("\u{2318}") }
        return names
    }

    private static let modifierKeyCodes: Set<Int> = [
        kVK_Command, kVK_RightCommand,
        kVK_Shift, kVK_RightShift,
        kVK_Option, kVK_RightOption,
        kVK_Control, kVK_RightControl,
        kVK_Function,
    ]

    private static func modifierDisplayName(for keyCode: Int) -> String {
        switch keyCode {
        case kVK_Command, kVK_RightCommand: return "\u{2318}"
        case kVK_Shift, kVK_RightShift:     return "\u{21E7}"
        case kVK_Option, kVK_RightOption:    return "\u{2325}"
        case kVK_Control, kVK_RightControl:  return "\u{2303}"
        case kVK_Function:                   return "fn"
        default:                             return "Mod"
        }
    }

    deinit {
        removeMonitors()
    }
}

#if DEBUG
#Preview {
    UnifiedShortcutRecorder(shortcut: .constant(.unconfigured))
        .padding(50)
}
#endif

#endif
