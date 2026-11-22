import AppKit
import Observation
import Sparkle

@Observable
@MainActor
final class CheckForUpdatesModel {
    var canCheckForUpdates = false

    private var pendingCheck = false
    private let updater: SPUUpdater
    private var observation: NSKeyValueObservation?

    init(updater: SPUUpdater) {
        self.updater = updater
        observation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.canCheckForUpdates = updater.canCheckForUpdates
                if self.pendingCheck && self.canCheckForUpdates { self.checkForUpdates() }
            }
        }
    }

    func checkWhenReady() {
        guard updater.canCheckForUpdates else {
            pendingCheck = true
            return
        }
        checkForUpdates()
    }

    func checkForUpdates() {
        pendingCheck = false
        updater.checkForUpdates()
    }
}
