import Shared
import SwiftUI

struct SettingsTabIcon: View {
    let tab: SettingsTab
    var size: CGFloat = 24

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size / 3, style: .continuous)
                .fill(tab.fill.gradient)
            Image(systemName: tab.symbol)
                .symbolVariant(.fill)
                .foregroundStyle(.white)
                .font(.system(size: size * 0.55, weight: .semibold))
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    VStack(alignment: .leading) {
        ForEach(SettingsTab.allCases, id: \.self) { tab in
            HStack { SettingsTabIcon(tab: tab); Text(tab.title) }
        }
    }
    .padding()
}
