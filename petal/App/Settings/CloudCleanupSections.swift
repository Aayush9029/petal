import CloudCleanupClient
import CloudCleanupFeature
import Shared
import SwiftUI

struct CloudCleanupSections: View {
    @Bindable var cloud: CloudCleanupModel

    var body: some View {
        SettingsPanelSection(title: "Cloud Provider") {
            CloudProviderPicker(selection: cloud.provider) { cloud.providerTapped($0) }
                .padding(14)

            SettingsCardDivider()

            if cloud.provider == .custom {
                SettingsControlRow(title: "Server URL", description: "Any OpenAI-compatible server, such as Ollama or LM Studio.") {
                    SettingsTextField(placeholder: "http://localhost:11434/v1", text: $cloud.serverURLInput)
                        .frame(width: 220)
                }

                SettingsCardDivider()
            }

            CloudAPIKeyField(
                provider: cloud.provider,
                apiKey: $cloud.apiKey,
                verification: cloud.verification,
                hasSavedKey: cloud.hasSavedKey,
                isUnsaved: cloud.isKeyUnsaved,
                onVerify: { Task { await cloud.verifyButtonTapped() } },
                onRemove: { cloud.removeKeyButtonTapped() }
            )
            .id(cloud.provider)

            SettingsCardDivider()

            CloudModelPicker(
                selection: cloud.selectedModel,
                modelList: cloud.modelList,
                search: { cloud.models(matching: $0) },
                onOpen: { await cloud.modelPickerOpened() },
                onReload: { await cloud.reloadModelsButtonTapped() },
                onSelect: { cloud.modelSelected($0) }
            )
        }

        SettingsPanelSection(title: "System Prompt") {
            CloudPromptPresetPicker(selection: cloud.selectedPreset) { cloud.presetTapped($0) }
                .padding(14)

            SettingsCardDivider()

            VStack(alignment: .leading, spacing: 10) {
                PromptPreview(text: cloud.systemPrompt) { cloud.promptEditorTapped() }

                if cloud.isTranscriptTagMissing {
                    TranscriptTagWarning { cloud.addTranscriptTagButtonTapped() }
                }

                HStack(alignment: .firstTextBaseline) {
                    Text("Click the prompt to edit it and insert variables, such as your name or the current app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if canResetPrompt {
                        SettingsActionButton(title: "Reset") { cloud.resetPromptButtonTapped() }
                    }
                }
            }
            .padding(14)
        }
        .sheet(item: $cloud.destination) { _ in
            PromptEditorSheet(
                text: Binding(cloud.$systemPrompt),
                isTranscriptTagMissing: cloud.isTranscriptTagMissing,
                canReset: canResetPrompt,
                onAddTranscriptTag: { cloud.addTranscriptTagButtonTapped() },
                onReset: { cloud.resetPromptButtonTapped() },
                onDone: { cloud.promptEditorDoneButtonTapped() }
            )
        }

        SettingsPanelSection(title: "Tools") {
            ForEach(CloudTool.allCases, id: \.self) { tool in
                if tool != CloudTool.allCases.first {
                    SettingsCardDivider()
                }
                SettingsToggleRow(
                    title: tool.title,
                    description: description(of: tool),
                    symbol: tool.symbol,
                    isOn: cloud.isToolEnabled(tool) && cloud.isToolAvailable(tool)
                ) { cloud.toolToggled(tool, isOn: $0) }
                .disabled(!cloud.isToolAvailable(tool))
                .opacity(cloud.isToolAvailable(tool) ? 1 : 0.5)
            }
        }
        .task(id: cloud.screenToolEnabled) { await cloud.screenRecordingPermissionTask() }

        SettingsPanelSection(title: "Try It") {
            CloudTestPanel(sample: $cloud.sampleTranscript, testRun: cloud.testRun) {
                Task { await cloud.runTestButtonTapped() }
            }
        }
    }

    private var canResetPrompt: Bool {
        cloud.systemPrompt != cloud.resetPreset.prompt
    }

    private func description(of tool: CloudTool) -> String {
        if !cloud.isToolAvailable(tool) { return "Not available for custom servers." }
        if cloud.isToolMissingPermission(tool) {
            return "Needs Screen Recording access. Allow Petal in Privacy & Security > Screen & System Audio Recording."
        }
        return tool.summary
    }
}
