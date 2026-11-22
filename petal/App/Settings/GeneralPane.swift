import AppFeature
import KeyboardShortcuts
import Shared
import SwiftUI

struct GeneralPane: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        SettingsPaneLayout {
            SettingsPanel {
                SettingsControlRow(
                    title: "Recording Shortcut",
                    description: viewModel.shortcutDescription,
                    symbol: "keyboard",
                    tint: .indigo
                ) {
                    UnifiedShortcutRecorder(shortcut: $viewModel.shortcut)
                }

                SettingsCardDivider()

                SettingsControlRow(
                    title: "Hold Duration",
                    symbol: "timer",
                    tint: .orange
                ) {
                    HoldDurationPicker(selection: viewModel.pushToTalkThreshold) { threshold in
                        viewModel.$pushToTalkThreshold.withLock { $0 = threshold }
                    }
                    .frame(width: 300)
                }

                SettingsCardDivider()

                SettingsControlRow(
                    title: "Paste Last Transcription",
                    description: "Paste your most recent transcription again.",
                    symbol: "doc.on.clipboard",
                    tint: .blue
                ) {
                    KeyboardShortcuts.Recorder(for: .pasteLastTranscription) { _ in viewModel.pasteLastTranscriptionShortcutRecorded() }
                }

                SettingsCardDivider()

                SettingsControlRow(
                    title: "Send Now",
                    description: "While recording, press ⌃X then ⌃S to stop, paste, and press Return.",
                    symbol: "return",
                    tint: .green
                ) {
                    KeyCapsLabel(keys: ["⌃X", "⌃S"])
                }
            }

            SettingsPanel {
                SettingsControlRow(
                    title: "Launch at Login",
                    description: viewModel.launchAtLoginMessage ?? "Open Petal automatically when you log in.",
                    symbol: "power",
                    tint: .gray
                ) {
                    SettingsSwitch(isOn: viewModel.launchAtLoginEnabled) { value in
                        Task { await viewModel.launchAtLoginToggled(value) }
                    }
                }
            }

            SettingsPanel {
                CapsuleAppearancePicker(selection: viewModel.floatingCapsuleBackgroundStyle) { style in
                    withAnimation(.snappy(duration: 0.24)) {
                        viewModel.$floatingCapsuleBackgroundStyle.withLock { $0 = style }
                    }
                }
                .padding(14)

                SettingsCardDivider()

                SettingsControlRow(
                    title: "Show Live Transcript",
                    description: "Show your words above the capsule as you speak. Works with models that transcribe live."
                ) {
                    SettingsSwitch(isOn: viewModel.showLiveTranscript) { value in
                        viewModel.$showLiveTranscript.withLock { $0 = value }
                    }
                }
            }

            if !viewModel.microphoneAuthorized || !viewModel.accessibilityAuthorized {
                SettingsPanel {
                    if !viewModel.microphoneAuthorized {
                        permissionRow(
                            title: "Microphone",
                            description: "Required to hear and transcribe your voice.",
                            symbol: "mic.fill",
                            tint: .pink
                        ) {
                            await viewModel.grantMicrophonePermissionButtonTapped()
                        }
                    }

                    if !viewModel.microphoneAuthorized && !viewModel.accessibilityAuthorized {
                        SettingsCardDivider()
                    }

                    if !viewModel.accessibilityAuthorized {
                        permissionRow(
                            title: "Accessibility",
                            description: "Allows Petal to paste into the app you are using.",
                            symbol: "accessibility",
                            tint: .blue
                        ) {
                            await viewModel.grantAccessibilityPermissionButtonTapped()
                        }
                    }

                    if let message = viewModel.permissionMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(14)
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task {
            await viewModel.refreshPermissions()
        }
        .animation(.smooth(duration: 0.3), value: viewModel.microphoneAuthorized)
        .animation(.smooth(duration: 0.3), value: viewModel.accessibilityAuthorized)
    }

    private func permissionRow(
        title: String,
        description: String,
        symbol: String,
        tint: Color,
        action: @escaping () async -> Void
    ) -> some View {
        SettingsControlRow(title: title, description: description, symbol: symbol, tint: tint) {
            SettingsActionButton(title: "Enable") {
                Task { await action() }
            }
        }
    }
}
