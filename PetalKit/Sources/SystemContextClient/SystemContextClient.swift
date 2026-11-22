import AppKit
import ApplicationServices
import Dependencies
import DependenciesMacros
import LogClient
import Shared

@DependencyClient
public struct SystemContextClient: Sendable {
    public var frontmostAppName: @Sendable () async -> String? = { nil }
    public var focusedApp: @Sendable () async -> FocusedApp? = { nil }
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
            focusedApp: {
                let front = await MainActor.run { () -> (pid: pid_t, app: MacApp)? in
                    guard let app = NSWorkspace.shared.frontmostApplication, let bundleID = app.bundleIdentifier else { return nil }
                    return (app.processIdentifier, MacApp(bundleID: bundleID, name: app.localizedName ?? bundleID))
                }
                guard let front else { return nil }
                let website = BrowserTab.bundleIDs.contains(front.app.bundleID)
                    ? BrowserTab.host(processIdentifier: front.pid)
                    : nil
                return FocusedApp(app: front.app, website: website)
            },
            frontmostWindowTitle: {
                guard let pid = await MainActor.run(body: { NSWorkspace.shared.frontmostApplication?.processIdentifier }) else {
                    return nil
                }
                let window = AXUIElementCreateApplication(pid).element(for: kAXFocusedWindowAttribute)
                let title = (window?.value(for: kAXTitleAttribute) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                return title?.isEmpty == false ? title : nil
            },
            userFullName: { NSFullUserName() },
            clipboardText: {
                await MainActor.run { NSPasteboard.general.string(forType: .string) }
            },
            selectedText: {
                AXUIElementCreateSystemWide().element(for: kAXFocusedUIElementAttribute)?.value(for: kAXSelectedTextAttribute) as? String
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
            focusedApp: { FocusedApp(app: MacApp(bundleID: "com.apple.Notes", name: "Notes")) },
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
