import AppKit
import ApplicationServices
import Dependencies
import DependenciesMacros
import LogClient

@DependencyClient
public struct SystemContextClient: Sendable {
    public var frontmostAppName: @Sendable () async -> String? = { nil }
    public var frontmostWindowTitle: @Sendable () async -> String? = { nil }
    public var userFullName: @Sendable () -> String = { "" }
    public var clipboardText: @Sendable () async -> String? = { nil }
    public var selectedText: @Sendable () async -> String? = { nil }
    public var screenshot: @Sendable () async -> Data? = { nil }
}

extension SystemContextClient: DependencyKey {
    public static var liveValue: Self {
        Self(
            frontmostAppName: {
                await MainActor.run { NSWorkspace.shared.frontmostApplication?.localizedName }
            },
            frontmostWindowTitle: {
                guard let pid = await MainActor.run(body: { NSWorkspace.shared.frontmostApplication?.processIdentifier }) else {
                    return nil
                }
                var window: CFTypeRef?
                guard AXUIElementCopyAttributeValue(
                    AXUIElementCreateApplication(pid),
                    kAXFocusedWindowAttribute as CFString,
                    &window
                ) == .success,
                    let window,
                    CFGetTypeID(window) == AXUIElementGetTypeID()
                else { return nil }
                var title: CFTypeRef?
                guard AXUIElementCopyAttributeValue(
                    unsafeDowncast(window, to: AXUIElement.self),
                    kAXTitleAttribute as CFString,
                    &title
                ) == .success,
                    let title = (title as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                    !title.isEmpty
                else { return nil }
                return title
            },
            userFullName: { NSFullUserName() },
            clipboardText: {
                await MainActor.run { NSPasteboard.general.string(forType: .string) }
            },
            selectedText: {
                var focused: CFTypeRef?
                guard AXUIElementCopyAttributeValue(
                    AXUIElementCreateSystemWide(),
                    kAXFocusedUIElementAttribute as CFString,
                    &focused
                ) == .success,
                    let focused,
                    CFGetTypeID(focused) == AXUIElementGetTypeID()
                else { return nil }
                var selected: CFTypeRef?
                guard AXUIElementCopyAttributeValue(
                    unsafeDowncast(focused, to: AXUIElement.self),
                    kAXSelectedTextAttribute as CFString,
                    &selected
                ) == .success else { return nil }
                return selected as? String
            },
            screenshot: {
                do {
                    return try await ScreenCapture.frontmostDisplayJPEG()
                } catch {
                    @Dependency(\.logClient) var logClient
                    logClient.error("SystemContextClient", "Screen capture failed: \(error)")
                    return nil
                }
            }
        )
    }

    public static var previewValue: Self {
        Self(
            frontmostAppName: { "Notes" },
            frontmostWindowTitle: { "Q4 launch plan" },
            userFullName: { "Alex Kim" },
            clipboardText: { "The launch moved to Tuesday." },
            selectedText: { nil },
            screenshot: { nil }
        )
    }

    public static var testValue: Self { Self() }
}

public extension DependencyValues {
    var systemContextClient: SystemContextClient {
        get { self[SystemContextClient.self] }
        set { self[SystemContextClient.self] = newValue }
    }
}
