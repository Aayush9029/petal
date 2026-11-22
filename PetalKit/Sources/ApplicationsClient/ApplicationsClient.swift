import AppKit
import Shared
import UniformTypeIdentifiers

@DependencyClient
public struct ApplicationsClient: Sendable {
    public var runningApplications: @MainActor @Sendable () -> AsyncStream<[MacApp]> = { AsyncStream { $0.finish() } }
    public var chooseApplication: @MainActor @Sendable () -> MacApp? = { nil }
}

extension ApplicationsClient: DependencyKey {
    public static var liveValue: Self {
        Self(
            runningApplications: {
                AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
                    let observation = NSWorkspace.shared.observe(\.runningApplications, options: [.initial, .new]) { workspace, _ in
                        var seen = Set<String>()
                        let apps = workspace.runningApplications.compactMap { app -> MacApp? in
                            guard app.activationPolicy == .regular,
                                  let id = app.bundleIdentifier,
                                  id != Bundle.main.bundleIdentifier,
                                  seen.insert(id).inserted
                            else { return nil }
                            return MacApp(bundleID: id, name: app.localizedName ?? id)
                        }
                        continuation.yield(apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
                    }
                    continuation.onTermination = { _ in observation.invalidate() }
                }
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
                AsyncStream { continuation in
                    continuation.yield([
                        MacApp(bundleID: "com.apple.mail", name: "Mail"),
                        MacApp(bundleID: "com.apple.MobileSMS", name: "Messages"),
                        MacApp(bundleID: "com.apple.Safari", name: "Safari"),
                        MacApp(bundleID: "com.apple.Terminal", name: "Terminal"),
                    ])
                    continuation.finish()
                }
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
