import AppKit
import ApplicationServices
import Dependencies
import DependenciesMacros

@DependencyClient
public struct SystemContextClient: Sendable {
    public var frontmostAppName: @Sendable () async -> String? = { nil }
    public var userFullName: @Sendable () -> String = { "" }
    public var clipboardText: @Sendable () async -> String? = { nil }
    public var selectedText: @Sendable () async -> String? = { nil }
}

extension SystemContextClient: DependencyKey {
    public static var liveValue: Self {
        Self(
            frontmostAppName: {
                await MainActor.run { NSWorkspace.shared.frontmostApplication?.localizedName }
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
            }
        )
    }

    public static var previewValue: Self {
        Self(
            frontmostAppName: { "Notes" },
            userFullName: { "Alex Kim" },
            clipboardText: { "The launch moved to Tuesday." },
            selectedText: { nil }
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
