import SwiftUI

extension View {
    func settingsSelection(_ isSelected: Bool, in shape: some InsettableShape) -> some View {
        modifier(SettingsSelectionModifier(isSelected: isSelected, shape: shape))
    }
}

private struct SettingsSelectionModifier<S: InsettableShape>: ViewModifier {
    let isSelected: Bool
    let shape: S

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .environment(\.colorScheme, isSelected ? inverted : colorScheme)
            .background {
                if isSelected {
                    shape.fill(colorScheme == .dark ? Color.white : Color.black)
                }
            }
    }

    private var inverted: ColorScheme {
        colorScheme == .dark ? .light : .dark
    }
}
