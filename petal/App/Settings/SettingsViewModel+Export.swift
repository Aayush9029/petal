import AppFeature
import AppKit
import UniformTypeIdentifiers

extension SettingsViewModel {
    func exportLogs() {
        guard let logURL = logFileURL else { return }
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = logURL.lastPathComponent
        savePanel.allowedContentTypes = [.plainText]
        guard savePanel.runModal() == .OK, let destination = savePanel.url else { return }
        do {
            try Data(contentsOf: logURL, options: .mappedIfSafe).write(to: destination, options: .atomic)
        } catch {
            NSApp.presentError(error)
        }
    }
}
