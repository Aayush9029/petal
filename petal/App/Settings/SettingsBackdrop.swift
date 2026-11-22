import SwiftUI

struct SettingsBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        SettingsDetailBackground()
            .overlay {
                if colorScheme == .dark {
                    Color.black.opacity(0.28)
                }
            }
            .ignoresSafeArea()
    }
}
