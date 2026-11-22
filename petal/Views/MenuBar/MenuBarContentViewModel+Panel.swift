import AppFeature
import AppKit
import Shared

extension MenuBarContentViewModel {
    func chooseAudioFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = AudioFileDropValidator.supportedContentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor [weak self] in
                await self?.audioFilesDropped([url])
            }
        }
    }

    func showAbout() {
        NSApp.sendAction(#selector(AppDelegate.showAboutPanel), to: nil, from: nil)
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }
}
