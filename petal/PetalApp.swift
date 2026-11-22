import AppFeature
import Dependencies
import Darwin
import os
import Carbon.HIToolbox
import PlaybackDuckingClient
import Sparkle
import SwiftUI
import WindowClient

@MainActor
struct PetalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        guard SingleInstanceLock.shared.acquire() else {
            Logger(subsystem: "com.optimalapps.petal", category: "App")
                .error("Another petal instance is already running. exiting duplicate process.")
            exit(0)
        }
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Petal") {
                    NSApp.sendAction(#selector(AppDelegate.showAboutPanel), to: nil, from: nil)
                }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    appDelegate.model.openSettingsWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

private final class SingleInstanceLock {
    static let shared = SingleInstanceLock()

    private var fileDescriptor: Int32 = -1
    private let lockPath = "\(NSTemporaryDirectory())com.optimalapps.petal.lock"

    private init() {}

    func acquire() -> Bool {
        if fileDescriptor != -1 {
            return true
        }

        let descriptor = open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor != -1 else { return false }

        if flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            close(descriptor)
            return false
        }

        fileDescriptor = descriptor
        return true
    }

    deinit {
        guard fileDescriptor != -1 else { return }
        flock(fileDescriptor, LOCK_UN)
        close(fileDescriptor)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) lazy var model = AppModel(
        isPreviewMode: ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    ) { [windowClient] appModel in
        NSApp.setActivationPolicy(.regular)
        Task {
            await windowClient.show(.settings, {
                let settings = withDependencies(from: appModel) { SettingsViewModel(appModel: appModel) }
                return NSHostingView(rootView: SettingsView(viewModel: settings))
            }, {
                NSApp.setActivationPolicy(.accessory)
            })
        }
    }
    private lazy var menuBarViewModel = MenuBarContentViewModel(appModel: model)
    private var statusItem: StatusItemController?

    private(set) lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil
    )
    private lazy var updatesModel = CheckForUpdatesModel(updater: updaterController.updater)
    @Dependency(\.windowClient) private var windowClient
    @Dependency(\.playbackDuckingClient) private var playbackDuckingClient
    private let logger = Logger(subsystem: "com.optimalapps.petal", category: "AppDelegate")
    private var pendingUpdateInstall: (() -> Void)?
    private static let updateInstallRetryInterval: TimeInterval = 30

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItemController(viewModel: menuBarViewModel)
        Task { await model.appDidLaunch() }
        registerDeepLinkAppleEventHandler()
        logger.info("Registered deep link AppleEvent handler")
        #if !DEBUG
        // Debug builds have build number 1, so Sparkle would install the release over them when they quit.
        updaterController.startUpdater()
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached { [playbackDuckingClient] in
            await playbackDuckingClient.stopDucking()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        logger.info("Received application(open:) URLs count=\(urls.count, privacy: .public)")
        for url in urls {
            guard let command = PetalDeepLinkCommand.parse(url) else { continue }
            logger.info("Parsed deep link from application(open:): \(command.rawValue, privacy: .public)")
            handleDeepLink(command)
        }
    }

    @objc
    func showAboutPanel() {
        NSApp.setActivationPolicy(.regular)
        let updatesModel = self.updatesModel
        Task {
            await windowClient.show(.about, {
                NSHostingView(rootView: AboutView(updatesModel: updatesModel))
            }, {
                NSApp.setActivationPolicy(.accessory)
            })
        }
    }

    private func registerDeepLinkAppleEventHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc
    private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent _: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString),
              let command = PetalDeepLinkCommand.parse(url)
        else { return }
        logger.info("Parsed deep link from kAEGetURL: \(command.rawValue, privacy: .public)")
        handleDeepLink(command)
    }

    private func handleDeepLink(_ command: PetalDeepLinkCommand) {
        if command == .checkForUpdates {
            updatesModel.checkWhenReady()
        } else {
            Task { await model.handleDeepLink(command) }
        }
    }

}

extension AppDelegate: SPUUpdaterDelegate {
    /// A menu bar app seldom quits, so a downloaded update is installed at the first idle moment and not on quit.
    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        logger.info("Update \(item.displayVersionString, privacy: .public) is downloaded. Installing when idle.")
        pendingUpdateInstall = immediateInstallHandler
        installPendingUpdateWhenIdle()
        return true
    }

    private func installPendingUpdateWhenIdle() {
        guard let install = pendingUpdateInstall else { return }
        let hasOpenWindow = NSApp.activationPolicy() != .accessory || menuBarViewModel.isPopupVisible
        guard model.isIdle, !hasOpenWindow else {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.updateInstallRetryInterval) { [weak self] in
                self?.installPendingUpdateWhenIdle()
            }
            return
        }
        pendingUpdateInstall = nil
        logger.info("Installing the downloaded update and relaunching")
        install()
    }
}
