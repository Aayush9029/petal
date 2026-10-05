import AppKit
import Shared
import UniformTypeIdentifiers

@DependencyClient
public struct ApplicationsClient: Sendable {
    /// Apps with a Dock presence, sorted by name, without Petal itself.
    public var runningApplications: @MainActor @Sendable () -> [MacApp] = { [] }
    /// Opens the Applications folder so the user can pick an app that is not running.
    public var chooseApplication: @MainActor @Sendable () -> MacApp? = { nil }
}

extension ApplicationsClient: DependencyKey {
    public static var liveValue: Self {
        Self(
            runningApplications: {
                var seen = Set<String>()
                return NSWorkspace.shared.runningApplications
                    .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
                    .compactMap { app -> MacApp? in
                        guard let bundleID = app.bundleIdentifier, seen.insert(bundleID).inserted else { return nil }
                        return MacApp(bundleID: bundleID, name: app.localizedName ?? bundleID)
                    }
                    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            },
            chooseApplication: {
                let panel = NSOpenPanel()
                panel.directoryURL = URL(filePath: "/Applications")
                panel.allowedContentTypes = [.application]
                panel.allowsMultipleSelection = false
                panel.canChooseDirectories = false
                panel.treatsFilePackagesAsDirectories = false
                panel.prompt = "Add"
                panel.message = "Choose an app to give it its own instructions."
                guard panel.runModal() == .OK,
                      let url = panel.url,
                      let bundleID = Bundle(url: url)?.bundleIdentifier
                else { return nil }
                let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
                return MacApp(bundleID: bundleID, name: name)
            }
        )
    }

    public static var previewValue: Self {
        Self(
            runningApplications: {
                [
                    MacApp(bundleID: "com.apple.mail", name: "Mail"),
                    MacApp(bundleID: "com.apple.MobileSMS", name: "Messages"),
                    MacApp(bundleID: "com.apple.Safari", name: "Safari"),
                    MacApp(bundleID: "com.apple.Terminal", name: "Terminal"),
                ]
            },
            chooseApplication: { MacApp(bundleID: "com.apple.Notes", name: "Notes") }
        )
    }

    public static var testValue: Self { Self() }
}

public extension DependencyValues {
    var applicationsClient: ApplicationsClient {
        get { self[ApplicationsClient.self] }
        set { self[ApplicationsClient.self] = newValue }
    }
}
