import RouterFeature
import Shared
import SwiftUI

struct RouteNode: View {
    let node: RouterFlowNode
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                RouteIcon(trigger: node.trigger, size: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(node.trigger?.title ?? "All Other Apps")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    HStack(spacing: 3) {
                        Image(systemName: node.style.symbol)
                            .symbolVariant(.fill)
                            .foregroundStyle(node.style.tint)
                        Text(node.style.nodeTitle)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                }

                Spacer(minLength: 4)
            }
            .padding(.horizontal, 9)
            .frame(height: RouterFlowLayout.nodeHeight)
            .background {
                nodeShape.fill(
                    LinearGradient(
                        colors: [Color.accentColor.opacity(isSelected ? 0.18 : 0), Color.accentColor.opacity(isSelected ? 0.04 : 0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            }
            .overlay {
                nodeShape
                    .strokeBorder(borderColor, lineWidth: isSelected ? 2 : 1)
            }
            .settingsGlass(in: nodeShape, tint: isSelected ? Color.accentColor.opacity(0.14) : nil)
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.14), value: isHovering)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var nodeShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }

    private var borderColor: Color {
        if isSelected { return .accentColor }
        if contrast == .increased { return .primary.opacity(0.55) }
        return .primary.opacity(isHovering ? 0.2 : 0.07)
    }
}

#Preview {
    VStack(spacing: 8) {
        RouteNode(node: RouterFlowNode(id: .fallback, trigger: .app(MacApp(bundleID: "com.apple.mail", name: "Mail")), style: .preset(.email)), isSelected: true) {}
        RouteNode(node: RouterFlowNode(id: .fallback, trigger: .website("github.com"), style: .custom), isSelected: false) {}
        RouteNode(node: RouterFlowNode(id: .fallback, trigger: nil, style: .pasteAsSaid), isSelected: false) {}
    }
    .frame(width: 260)
    .padding()
}
