import RouterFeature
import Shared
import SwiftUI

struct RouteStylePicker: View {
    let selection: RouterModel.Style
    /// Names what Custom applies to, such as "Xcode" or "all other apps".
    let target: String
    let onPreset: (CloudPromptPreset) -> Void
    let onCustom: () -> Void
    let onPasteAsSaid: () -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(CloudPromptPreset.allCases) { preset in
                card(.preset(preset), subtitle: preset.shortSummary) { onPreset(preset) }
            }
            card(.custom, subtitle: "For \(target)", action: onCustom)
            card(.pasteAsSaid, subtitle: "No cleanup", action: onPasteAsSaid)
        }
    }

    private func card(_ style: RouterModel.Style, subtitle: String, action: @escaping () -> Void) -> some View {
        SelectableCard(isSelected: selection == style, action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Image(systemName: style.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(height: 18)
                    .padding(.bottom, 4)
                Text(style.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(4)
        }
        .help(style.summary)
        .accessibilityLabel("\(style.title), \(subtitle)")
    }
}

#Preview {
    VStack(spacing: 20) {
        RouteStylePicker(selection: .preset(.email), target: "Xcode", onPreset: { _ in }, onCustom: {}, onPasteAsSaid: {})
        RouteStylePicker(selection: .custom, target: "all other apps", onPreset: { _ in }, onCustom: {}, onPasteAsSaid: {})
    }
    .frame(width: 440)
    .padding()
}
