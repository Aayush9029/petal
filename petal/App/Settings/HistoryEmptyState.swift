import Shared
import SwiftUI

struct HistoryEmptyState: View {
    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(SettingsTab.history.fill.opacity(0.12))
                    .frame(width: 112, height: 112)
                SettingsIconTile(symbol: "waveform", fill: SettingsTab.history.fill, size: 64)
                    .shadow(color: SettingsTab.history.fill.opacity(0.35), radius: 10, y: 4)
            }
            .padding(.bottom, 4)

            VStack(spacing: 4) {
                Text("No Recordings")
                    .font(.title3.weight(.semibold))
                Text("Your saved recordings will appear here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    HistoryEmptyState()
        .frame(width: 480, height: 400)
}
