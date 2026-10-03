import Shared
import SwiftUI

struct CloudPromptPresetPicker: View {
    let selection: CloudPromptPreset?
    let onSelect: (CloudPromptPreset) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(CloudPromptPreset.allCases) { preset in
                SelectableCard(isSelected: selection == preset) {
                    onSelect(preset)
                } content: {
                    card(preset)
                }
                .help(preset.summary)
            }
        }
    }

    private func card(_ preset: CloudPromptPreset) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: preset.symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(height: 16)
            Text(preset.title)
                .font(.subheadline.weight(.semibold))
            Text(preset.summary)
                .font(.caption2)
                .opacity(0.7)
                .lineLimit(2, reservesSpace: true)
        }
        .padding(4)
    }
}

#Preview {
    @Previewable @State var preset: CloudPromptPreset? = .cleanUp
    CloudPromptPresetPicker(selection: preset) { preset = $0 }
        .frame(width: 470)
        .padding()
}
