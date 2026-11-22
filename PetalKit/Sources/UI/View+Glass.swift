import SwiftUI

/// Every Liquid Glass availability fork Petal owns lives here, so layout code never branches on the OS version.
public extension View {
    @ViewBuilder
    func petalGlass(cornerRadius: CGFloat) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            background {
                VisualEffectBackground(material: .hudWindow, blendingMode: .withinWindow)
                    .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
            }
        }
    }
}
