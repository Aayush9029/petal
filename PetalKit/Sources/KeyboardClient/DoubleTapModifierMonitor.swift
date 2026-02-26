import AppKit
import Carbon.HIToolbox
import Shared

/// Monitors `flagsChanged` CGEvents to detect a quick double-tap on a single
/// modifier key.  The callback fires only when:
///   1. The chosen modifier is pressed and released twice in quick succession.
///   2. No other key (including other modifiers) is pressed between the taps.
///   3. Each individual press is shorter than `maxPressDuration`.
///
/// This intentionally does **not** interfere with normal modifier usage such as
/// holding Command to perform Command+C, because we only count *full taps*
/// (press + release) and reset state whenever extra keys appear.
@MainActor
public final class DoubleTapModifierMonitor {
    // MARK: - Configuration

    /// Which modifier key to watch for.
    public var modifierKey: DoubleTapModifierKey {
        didSet { reset() }
    }

    /// Maximum elapsed time between the first tap's release and the second
    /// tap's press.  Defaults to 0.4 s.
    public var maxGapBetweenTaps: TimeInterval = 0.4

    /// Maximum time a single press can be held before it stops counting as a
    /// "tap".  Defaults to 0.3 s.
    public var maxPressDuration: TimeInterval = 0.3

    /// Called on the main thread when a valid double-tap is detected.
    public var onDoubleTap: (() -> Void)?

    // MARK: - Private state

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Timestamp of the most recent modifier-down transition.
    private var pressStart: Date?
    /// Timestamp of the first tap's release.
    private var firstTapRelease: Date?
    /// The set of modifier flags at the last `flagsChanged` event.
    private var previousFlags: CGEventFlags = []
    /// Whether we observed a non-modifier key between taps (invalidates the
    /// double-tap).
    private var otherKeyInterrupted = false

    // MARK: - Public API

    public init(modifierKey: DoubleTapModifierKey, onDoubleTap: (() -> Void)? = nil) {
        self.modifierKey = modifierKey
        self.onDoubleTap = onDoubleTap
    }

    deinit {
        stop()
    }

    public func start() {
        stop()
        reset()

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passRetained(event) }
            let monitor = Unmanaged<DoubleTapModifierMonitor>.fromOpaque(userInfo)
                .takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = monitor.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passRetained(event)
            }

            monitor.handleEvent(type: type, event: event)
            return Unmanaged.passRetained(event)
        }

        let eventsOfInterest: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: eventsOfInterest,
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

    public func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            self.eventTap = nil
        }

        reset()
    }

    // MARK: - Event handling

    private func handleEvent(type: CGEventType, event: CGEvent) {
        if type == .keyDown {
            // A regular key was pressed – invalidate any in-progress
            // double-tap sequence so we don't fire while the user is typing.
            otherKeyInterrupted = true
            return
        }

        guard type == .flagsChanged else { return }

        let flags = event.flags
        let targetMask = cgEventMask(for: modifierKey)

        let wasPressed = previousFlags.contains(targetMask)
        let isPressed = flags.contains(targetMask)
        previousFlags = flags

        // Ignore events that don't change the target modifier.
        guard wasPressed != isPressed else { return }

        // If any *other* modifier changed at the same time, reset.
        let relevantFlags: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn]
        let otherFlags = relevantFlags.subtracting(targetMask)
        if !flags.intersection(otherFlags).isEmpty {
            reset()
            return
        }

        let now = Date()

        if isPressed {
            // Modifier went down.
            pressStart = now
        } else {
            // Modifier went up – this completes a single tap.
            guard let start = pressStart else {
                reset()
                return
            }

            let pressDuration = now.timeIntervalSince(start)
            pressStart = nil

            guard pressDuration <= maxPressDuration else {
                // Press was too long; treat as a hold, not a tap.
                reset()
                return
            }

            if let firstRelease = firstTapRelease {
                // This is the second tap.
                let gap = now.timeIntervalSince(firstRelease)
                if gap <= maxGapBetweenTaps, !otherKeyInterrupted {
                    onDoubleTap?()
                }
                // Always reset after evaluating the second tap.
                reset()
            } else {
                // This is the first tap – record it.
                firstTapRelease = now
                otherKeyInterrupted = false
            }
        }
    }

    private func reset() {
        pressStart = nil
        firstTapRelease = nil
        otherKeyInterrupted = false
    }

    // MARK: - Helpers

    private func cgEventMask(for key: DoubleTapModifierKey) -> CGEventFlags {
        switch key {
        case .fn: return .maskSecondaryFn
        case .command: return .maskCommand
        case .option: return .maskAlternate
        case .control: return .maskControl
        case .shift: return .maskShift
        }
    }
}
