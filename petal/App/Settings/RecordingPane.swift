import AppFeature
import Assets
import AudioClient
import Shared
import SwiftUI

struct RecordingPane: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        SettingsPaneLayout {
            SettingsPanel {
                SettingsControlRow(title: "Microphone", symbol: "mic", tint: .pink) {
                    SettingsMenuPicker(
                        values: viewModel.audioInputDevices,
                        selection: viewModel.selectedAudioInput,
                        title: \.name
                    ) { device in
                        viewModel.selectedAudioInput = device
                    }
                    .frame(maxWidth: 220)
                }

                if viewModel.offersSpokenLanguageChoice {
                    SettingsCardDivider()

                    SettingsControlRow(
                        title: "Spoken Language",
                        description: "Qwen3 ASR and Whisper use this language. Other models detect it.",
                        symbol: "character.bubble",
                        tint: .blue
                    ) {
                        SettingsMenuPicker(
                            values: [nil] + SpokenLanguage.allCases.map(Optional.some),
                            selection: viewModel.spokenLanguage,
                            title: { $0?.name ?? "Automatic" }
                        ) { language in
                            viewModel.spokenLanguagePicked(language)
                        }
                    }
                }
            }

            SettingsGlassContainer {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                    RecordingOptionTile(
                        title: "Trim Silence",
                        description: "Remove quiet gaps from recordings.",
                        symbol: "scissors",
                        artwork: .recordingTrimSilence,
                        isOn: viewModel.trimSilenceEnabled
                    ) { viewModel.$trimSilenceEnabled.withLock { $0.toggle() } }

                    RecordingOptionTile(
                        title: "Auto Speed-up",
                        description: "Accelerate long recordings automatically.",
                        symbol: "hare",
                        artwork: .recordingAutoSpeed,
                        isOn: viewModel.autoSpeedEnabled
                    ) { viewModel.$autoSpeedEnabled.withLock { $0.toggle() } }

                    RecordingOptionTile(
                        title: "Restore Clipboard",
                        description: "Put previous clipboard content back.",
                        symbol: "clipboard",
                        artwork: .recordingRestoreClipboard,
                        isOn: viewModel.restoreClipboardAfterPaste
                    ) { viewModel.$restoreClipboardAfterPaste.withLock { $0.toggle() } }

                    RecordingOptionTile(
                        title: "Lower System Audio",
                        description: "Quiet other audio while recording.",
                        symbol: "speaker.wave.1",
                        artwork: .recordingLowerAudio,
                        isOn: viewModel.duckSystemAudioDuringRecording
                    ) { viewModel.$duckSystemAudioDuringRecording.withLock { $0.toggle() } }
                }
            }
        }
        .task {
            await viewModel.refreshAudioInputDevices()
        }
    }
}
