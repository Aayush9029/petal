import SwiftUI

/// Dims the desktop tint in Dark Mode, so the glass cards stand out from the window.
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
