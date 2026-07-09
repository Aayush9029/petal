import SwiftUI

struct AccessibilityCapsuleButton: View {
    let blur: CGFloat
    let openSettings: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: openSettings) {
            HStack(spacing: 8) {
                DottedStatusGlyph(
                    kind: .accessibility,
                    tint: isHovering ? .white : .blue
                )

                Text("Enable Accessibility")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(isHovering ? Color.white : Color.primary)
            }
            .floatingCapsuleChrome(blur: blur, highlight: isHovering ? .blue : nil)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.smooth(duration: 0.18), value: isHovering)
        .onHover { isHovering = $0 }
        .help("Open Accessibility settings")
    }
}
