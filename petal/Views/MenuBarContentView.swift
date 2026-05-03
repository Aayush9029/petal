import Shared
import SwiftUI

struct MenuBarContentView: View {
    @Bindable var viewModel: MenuBarContentViewModel

    var body: some View {
        Text(viewModel.statusTitle)
            .foregroundStyle(viewModel.statusColor)

        if viewModel.isRecording {
            Button("Stop Recording") {
                viewModel.stopRecording()
            }
        }

        if let error = viewModel.statusErrorMessage {
            Text(error)
                .foregroundStyle(.red)
        }

        if !viewModel.isRecording, let message = viewModel.transientMessage {
            Text(message)
                .foregroundStyle(.secondary)
        }

        Divider()

        if viewModel.shouldShowPermissionsSection {
            if viewModel.needsMicrophonePermission {
                Button("Grant Microphone Access") {
                    viewModel.requestMicrophonePermission()
                }
            }

            if viewModel.needsAccessibilityPermission {
                Button("Enable Accessibility Access") {
                    viewModel.requestAccessibilityPermission()
                }
            }
        }

        if viewModel.shouldShowHistoryMenu {
            Menu("History") {
                if viewModel.historyMenuItems.isEmpty {
                    Text("No transcripts yet")
                } else {
                    ForEach(viewModel.historyMenuItems) { item in
                        Button {
                            viewModel.copyHistoryEntry(item.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                Text(item.subtitle)
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
        }

        Divider()

        if viewModel.showsCheckForUpdates {
            Button("Check for Updates…") {
                viewModel.checkForUpdates()
            }
            .disabled(!viewModel.canCheckForUpdates)
        }

        Button("About Petal") {
            viewModel.showAbout()
        }

        Button("Settings…") {
            viewModel.openSettings()
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit Petal") {
            viewModel.quit()
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}

#Preview("Ready") {
    let model = AppModel.makePreview()
    MenuBarContentView(viewModel: MenuBarContentViewModel(appModel: model))
}

#Preview("Needs Permissions") {
    let model = AppModel.makePreview { model in
        model.microphoneAuthorized = false
        model.accessibilityAuthorized = false
        model.transientMessage = "Permissions are required before recording."
    }

    MenuBarContentView(viewModel: MenuBarContentViewModel(appModel: model))
}

#Preview("With History") {
    let model = AppModel.makePreview { model in
        model.$transcriptHistoryDays.withLock { $0 = [
            TranscriptHistoryDay(
                day: "2026-02-20",
                entries: [
                    TranscriptHistoryEntry(
                        id: UUID(),
                        timestamp: Date(),
                        modelID: ModelOption.whisperLargeV3Turbo.rawValue,
                        audioDurationSeconds: 5.8,
                        audioRelativePath: "audio/clip1.m4a",
                        variants: [
                            TranscriptHistoryVariant(
                                mode: "smart",
                                transcriptionElapsedSeconds: 1.9,
                                characterCount: 57,
                                pasteResult: "pasted",
                                transcriptRelativePath: "transcripts/clip1.txt"
                            )
                        ]
                    )
                ]
            )
        ] }
    }

    MenuBarContentView(viewModel: MenuBarContentViewModel(appModel: model))
}
