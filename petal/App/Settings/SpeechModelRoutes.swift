import Shared
import SwiftUI

/// Chooses the speech model for each kind of work: dictation needs a fast model, and an audio file can wait for a more accurate one.
struct SpeechModelRoutes: View {
    let models: [ModelOption]
    let dictationModel: ModelOption?
    let fileModel: ModelOption?
    let onDictationModel: (ModelOption) -> Void
    let onFileModel: (ModelOption?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            row(
                title: "Dictation",
                description: "Runs each time you record, so a fast model works best.",
                systemImage: "mic.fill"
            ) {
                Picker("Dictation", selection: dictationSelection) {
                    ForEach(models) { model in
                        Text(model.displayName).tag(ModelOption?.some(model))
                    }
                }
            }

            SettingsCardDivider()

            row(
                title: "Audio Files",
                description: "Dropped and chosen files can use a slower, more accurate model.",
                systemImage: "waveform"
            ) {
                Picker("Audio Files", selection: fileSelection) {
                    Text("Same as Dictation").tag(ModelOption?.none)
                    ForEach(models.filter { $0 != dictationModel }) { model in
                        Text(model.displayName).tag(ModelOption?.some(model))
                    }
                }
            }
        }
    }

    private var dictationSelection: Binding<ModelOption?> {
        Binding(get: { dictationModel }, set: { if let model = $0 { onDictationModel(model) } })
    }

    private var fileSelection: Binding<ModelOption?> {
        Binding(get: { fileModel }, set: { onFileModel($0) })
    }

    private func row(
        title: String,
        description: String,
        systemImage: String,
        @ViewBuilder picker: () -> some View
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            picker()
                .labelsHidden()
                .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview {
    SpeechModelRoutes(
        models: [.parakeetTDTCTC110M, .nemotronUnified06B, .qwen3ASR17B8bit],
        dictationModel: .parakeetTDTCTC110M,
        fileModel: .qwen3ASR17B8bit,
        onDictationModel: { _ in },
        onFileModel: { _ in }
    )
    .frame(width: 480)
}
