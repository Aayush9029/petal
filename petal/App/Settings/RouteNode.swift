import RouterFeature
import Shared
import SwiftUI

struct RouteNode: View {
    let node: RouterFlowNode
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                RouteIcon(trigger: node.trigger, size: 26)

                VStack(alignment: .leading, spacing: 1) {
                    Text(node.trigger?.title ?? "All Other Apps")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    HStack(spacing: 3) {
                        Image(systemName: node.style.symbol)
                        Text(node.style.nodeTitle)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                Spacer(minLength: 4)
            }
            .padding(.horizontal, 9)
            .frame(height: RouterFlowLayout.nodeHeight)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(Color.accentColor.opacity(isSelected ? 0.1 : 0))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color(nsColor: .separatorColor).opacity(isHovering ? 1 : 0.7),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
            .contentShape(.rect(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.14), value: isHovering)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
