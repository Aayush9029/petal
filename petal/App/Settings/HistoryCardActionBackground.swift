import SwiftUI

struct HistoryCardActionBackground: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .font(.callout.weight(.medium))
            .frame(width: 28, height: 28)
            .background(Color.primary.opacity(isHovering ? 0.12 : 0.06), in: .circle)
            .contentShape(.circle)
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}
