import AppKit
import Dependencies
import DependenciesMacros
import os.log
import Sauce

private let logger = Logger(subsystem: "com.optimalapps.petal", category: "KeyboardClient")

public enum KeyPress: Equatable, Sendable {
    case escape
    case `return`
    case character(Character)
    /// A letter pressed with Control and no Command or Option, such as Control-X.
    case control(Character)
    case other
}

/// Return `true` from the handler to swallow the event (prevent it from reaching text fields).
public typealias KeyPressHandler = @Sendable (KeyPress) -> Bool

@DependencyClient
public struct KeyboardClient: Sendable {
    public var start: @Sendable (@escaping KeyPressHandler) async -> Void = { _ in }
    public var stop: @Sendable () async -> Void = {}
}

extension KeyboardClient: DependencyKey {
    public static var liveValue: Self {
        return Self(
            start: { handler in
                await MainActor.run { LiveKeyboardRuntimeContainer.shared.start(handler: handler) }
            },
            stop: {
                await MainActor.run { LiveKeyboardRuntimeContainer.shared.stop() }
            }
        )
    }
}

extension KeyboardClient: TestDependencyKey {
    public static var testValue: Self {
        Self(
            start: { _ in },
            stop: { }
        )
    }
}

public extension DependencyValues {
    var keyboardClient: KeyboardClient {
        get { self[KeyboardClient.self] }
        set { self[KeyboardClient.self] = newValue }
    }
}

@MainActor
private final class LiveKeyboardRuntime {
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var handler: KeyPressHandler?

    func start(handler: @escaping KeyPressHandler) {
        stop()
        self.handler = handler

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = self?.handle(event) ?? false
            return consumed ? nil : event
        }

        installEventTap()
    }

    func stop() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }

        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            self.eventTap = nil
        }

        handler = nil
    }

    private func installEventTap() {
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passRetained(event) }
            let runtime = Unmanaged<LiveKeyboardRuntime>.fromOpaque(userInfo)
                .takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                logger.warning("CGEvent tap was disabled (type=\(String(describing: type))), re-enabling")
                if let tap = runtime.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passRetained(event)
            }

            guard let nsEvent = NSEvent(cgEvent: event) else {
                return Unmanaged.passRetained(event)
            }

            let consumed = runtime.handle(nsEvent)
            return consumed ? nil : Unmanaged.passRetained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: callback,
            userInfo: userInfo
        ) else {
            logger.error("CGEvent tap creation failed — falling back to global NSEvent monitor")
            installGlobalMonitor()
            return
        }

        logger.info("CGEvent tap installed successfully")
        eventTap = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func installGlobalMonitor() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
        }
        if globalMonitor != nil {
            logger.info("Global NSEvent monitor installed as fallback")
        } else {
            logger.error("Global NSEvent monitor also failed to install")
        }
    }

    @discardableResult
    private func handle(_ event: NSEvent) -> Bool {
        guard let handler else { return false }
        return handler(Self.keyPress(from: event))
    }

    private static func keyPress(from event: NSEvent) -> KeyPress {
        let sauceKey = Sauce.shared.key(for: Int(event.keyCode))
        if sauceKey == .escape { return .escape }
        if sauceKey == .return { return .return }

        guard let characters = event.charactersIgnoringModifiers, characters.count == 1 else {
            return .other
        }

        let normalized = characters.lowercased()
        guard let character = normalized.first else {
            return .other
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.control), modifiers.isDisjoint(with: [.command, .option]) {
            return .control(character)
        }
        return .character(character)
    }
}

@MainActor
private enum LiveKeyboardRuntimeContainer {
    static let shared = LiveKeyboardRuntime()
}
