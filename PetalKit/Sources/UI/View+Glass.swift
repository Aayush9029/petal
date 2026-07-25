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

    @ViewBuilder
    func petalGlassCapsule(id: String? = nil, in namespace: Namespace.ID? = nil) -> some View {
        if #available(macOS 26, *) {
            morphingGlassCapsule(id: id, in: namespace)
        } else {
            background {
                VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
                    .clipShape(.capsule)
            }
        }
    }
}

private extension View {
    /// A shared id and namespace let one capsule matched-geometry morph between statuses instead of cross-fading two surfaces.
    @available(macOS 26, *)
    @ViewBuilder
    func morphingGlassCapsule(id: String?, in namespace: Namespace.ID?) -> some View {
        if let id, let namespace {
            glassEffect(in: .capsule).glassEffectID(id, in: namespace)
        } else {
            glassEffect(in: .capsule)
        }
    }
}
