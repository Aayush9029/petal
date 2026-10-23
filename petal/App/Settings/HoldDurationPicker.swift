import Shared
import SwiftUI

struct HoldDurationPicker: View {
    let selection: PushToTalkThreshold
    let onSelect: (PushToTalkThreshold) -> Void

    private var longestSeconds: Double {
        PushToTalkThreshold.allCases.map(\.seconds).max() ?? 1
    }

    var body: some View {
        SettingsGlassContainer {
            HStack(spacing: 8) {
                ForEach(PushToTalkThreshold.allCases) { threshold in
                    SelectableCard(isSelected: selection == threshold) {
                        onSelect(threshold)
                    } content: {
                        card(threshold)
                    }
                }
            }
        }
    }

    private func card(_ threshold: PushToTalkThreshold) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 4) {
                Text(threshold.displayName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Spacer(minLength: 0)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.accentColor)
                    .opacity(selection == threshold ? 1 : 0)
            }

            HoldDurationPreview(
                seconds: threshold.seconds,
                longestSeconds: longestSeconds,
                tint: tint(isSelected: selection == threshold)
            )
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    private func tint(isSelected: Bool) -> Color {
        isSelected ? .accentColor : .primary
    }
}

#Preview {
    @Previewable @State var threshold = PushToTalkThreshold.medium
    HoldDurationPicker(selection: threshold) { threshold = $0 }
        .frame(width: 300)
        .padding()
}
