import AppKit
import Carbon.HIToolbox
import Shared

@MainActor
final class LiveDoubleTapRuntime {
    private enum TapState {
        case idle
        case firstTapDown(Date)
        case firstTapUp(Date)
        case secondTapDown(Date)
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var configuredKey: DoubleTapKey?
    private var interval: TimeInterval = 0.4
    private var onKeyDown: (@Sendable () -> Void)?
    private var onKeyUp: (@Sendable () -> Void)?

    private var state: TapState = .idle
    private var isSecondTapHeld = false

    func start(
        key: DoubleTapKey,
        interval: TimeInterval,
        onKeyDown: @escaping @Sendable () -> Void,
        onKeyUp: @escaping @Sendable () -> Void
    ) {
        stop()
        self.configuredKey = key
        self.interval = interval
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp
        self.state = .idle
        self.isSecondTapHeld = false
        installEventTap()
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            self.eventTap = nil
        }
        configuredKey = nil
        onKeyDown = nil
        onKeyUp = nil
        state = .idle
        isSecondTapHeld = false
    }

    private func installEventTap() {
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passRetained(event) }
            let runtime = Unmanaged<LiveDoubleTapRuntime>.fromOpaque(userInfo)
                .takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = runtime.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passRetained(event)
            }

            runtime.handleEvent(type: type, event: event)
            return Unmanaged.passRetained(event)
        }

        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: userInfo
        ) else {
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handleEvent(type: CGEventType, event: CGEvent) {
        guard let key = configuredKey else { return }
        let now = Date()

        if key.isModifier {
            guard type == .flagsChanged else {
                // Another key type event — reset if we're waiting
                resetIfNotHeld()
                return
            }
            handleModifierEvent(event: event, key: key, now: now)
        } else {
            guard type == .keyDown || type == .keyUp else {
                // flagsChanged while waiting for regular key — reset (concurrent modifier)
                if type == .flagsChanged, hasConcurrentModifiers(event: event) {
                    resetIfNotHeld()
                }
                return
            }
            handleRegularKeyEvent(type: type, event: event, key: key, now: now)
        }
    }

    private func handleModifierEvent(event: CGEvent, key: DoubleTapKey, now: Date) {
        let flags = event.flags
        let isDown = isModifierDown(flags: flags, keyCode: key.keyCode)
        let hasConcurrent = hasConcurrentModifiersForModifier(flags: flags)

        if hasConcurrent {
            resetIfNotHeld()
            return
        }

        switch (state, isDown) {
        case (.idle, true):
            state = .firstTapDown(now)

        case (.firstTapDown, false):
            state = .firstTapUp(now)

        case let (.firstTapUp(firstUpTime), true):
            if now.timeIntervalSince(firstUpTime) <= interval {
                state = .secondTapDown(now)
                isSecondTapHeld = true
                onKeyDown?()
            } else {
                state = .firstTapDown(now)
            }

        case (.secondTapDown, false):
            isSecondTapHeld = false
            onKeyUp?()
            state = .idle

        default:
            break
        }
    }

    private func handleRegularKeyEvent(type: CGEventType, event: CGEvent, key: DoubleTapKey, now: Date) {
        let eventKeyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        guard eventKeyCode == key.keyCode else {
            resetIfNotHeld()
            return
        }

        let isDown = type == .keyDown
        // Ignore key-repeat events (auto-repeat)
        if isDown, event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            return
        }

        switch (state, isDown) {
        case (.idle, true):
            state = .firstTapDown(now)

        case (.firstTapDown, false):
            state = .firstTapUp(now)

        case let (.firstTapUp(firstUpTime), true):
            if now.timeIntervalSince(firstUpTime) <= interval {
                state = .secondTapDown(now)
                isSecondTapHeld = true
                onKeyDown?()
            } else {
                state = .firstTapDown(now)
            }

        case (.secondTapDown, false):
            isSecondTapHeld = false
            onKeyUp?()
            state = .idle

        default:
            break
        }
    }

    private func resetIfNotHeld() {
        guard !isSecondTapHeld else { return }
        state = .idle
    }

    private func isModifierDown(flags: CGEventFlags, keyCode: Int) -> Bool {
        switch keyCode {
        case kVK_Command, kVK_RightCommand:
            return flags.contains(.maskCommand)
        case kVK_Shift, kVK_RightShift:
            return flags.contains(.maskShift)
        case kVK_Option, kVK_RightOption:
            return flags.contains(.maskAlternate)
        case kVK_Control, kVK_RightControl:
            return flags.contains(.maskControl)
        case kVK_Function:
            return flags.contains(.maskSecondaryFn)
        default:
            return false
        }
    }

    private func hasConcurrentModifiersForModifier(flags: CGEventFlags) -> Bool {
        var count = 0
        if flags.contains(.maskCommand) { count += 1 }
        if flags.contains(.maskShift) { count += 1 }
        if flags.contains(.maskAlternate) { count += 1 }
        if flags.contains(.maskControl) { count += 1 }
        return count > 1
    }

    private func hasConcurrentModifiers(event: CGEvent) -> Bool {
        let flags = event.flags
        var count = 0
        if flags.contains(.maskCommand) { count += 1 }
        if flags.contains(.maskShift) { count += 1 }
        if flags.contains(.maskAlternate) { count += 1 }
        if flags.contains(.maskControl) { count += 1 }
        return count > 0
    }
}

@MainActor
enum LiveDoubleTapRuntimeContainer {
    static let shared = LiveDoubleTapRuntime()
}
