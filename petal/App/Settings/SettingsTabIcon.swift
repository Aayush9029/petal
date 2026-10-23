import Shared
import SwiftUI

struct SettingsTabIcon: View {
    let tab: SettingsTab
    var size: CGFloat = 24

    var body: some View {
        SettingsIconTile(symbol: tab.symbol, fill: tab.fill, size: size)
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
