import AppKit
import Carbon.HIToolbox
import Shared

@MainActor
final class LiveDoubleTapRuntime {
    static let shared = LiveDoubleTapRuntime()

    private enum TapState {
        case idle
        case firstTapDown
        case firstTapUp(Date)
        case secondTapDown
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var configuredKey: DoubleTapKey?
    private var interval: TimeInterval = 0.4
    private var onKeyDown: (@Sendable () -> Void)?
    private var onKeyUp: (@Sendable () -> Void)?

    private var state: TapState = .idle

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
    }

    private func installEventTap() {
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let runtime = Unmanaged<LiveDoubleTapRuntime>.fromOpaque(userInfo)
                .takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = runtime.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }

            runtime.handleEvent(type: type, event: event)
            return Unmanaged.passUnretained(event)
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
        let modifiers = event.flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])
        let isDown: Bool
        if key.isModifier {
            guard type == .flagsChanged, modifiers.rawValue.nonzeroBitCount <= 1 else {
                resetIfNotHeld()
                return
            }
            isDown = isModifierDown(flags: event.flags, keyCode: key.keyCode)
        } else {
            if type == .flagsChanged {
                if !modifiers.isEmpty { resetIfNotHeld() }
                return
            }
            guard event.getIntegerValueField(.keyboardEventKeycode) == key.keyCode else {
                resetIfNotHeld()
                return
            }
            isDown = type == .keyDown
            if isDown, event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return }
        }

        let now = Date()
        switch (state, isDown) {
        case (.idle, true):
            state = .firstTapDown
        case (.firstTapDown, false):
            state = .firstTapUp(now)
        case let (.firstTapUp(releasedAt), true):
            if now.timeIntervalSince(releasedAt) <= interval {
                state = .secondTapDown
                onKeyDown?()
            } else {
                state = .firstTapDown
            }
        case (.secondTapDown, false):
            state = .idle
            onKeyUp?()
        default:
            break
        }
    }

    private func resetIfNotHeld() {
        if case .secondTapDown = state { return }
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
}
