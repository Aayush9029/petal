import RouterFeature
import Shared
import SwiftUI

/// Voice flows down into the router, which sends it along one branch per app. The selected branch is the one the inspector edits.
struct RouterFlowChart<AddButton: View>: View {
    let nodes: [RouterFlowNode]
    let selection: RouterModel.Selection
    let routerCaption: String
    let isFlowing: Bool
    let onSelect: (RouterModel.Selection) -> Void
    @ViewBuilder let addButton: () -> AddButton

    var body: some View {
        VStack(spacing: 0) {
            hubs
                .frame(height: RouterFlowLayout.headerHeight, alignment: .top)
            VStack(spacing: RouterFlowLayout.rowSpacing) {
                ForEach(0 ..< RouterFlowLayout.rows(slots: slotCount), id: \.self) { row in
                    HStack(spacing: 0) {
                        slot(row * 2)
                            .frame(maxWidth: .infinity)
                        Spacer()
                            .frame(width: RouterFlowLayout.spineGap)
                        slot(row * 2 + 1)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(height: RouterFlowLayout.nodeHeight)
                }
            }
        }
        .frame(height: RouterFlowLayout.height(slots: slotCount))
        .background(alignment: .top) {
            RouterFlowConnectors(slotCount: slotCount, activeSlot: activeSlot, isFlowing: isFlowing)
        }
    }

    private var slotCount: Int {
        nodes.count + 1
    }

    private var activeSlot: Int? {
        nodes.firstIndex { $0.id == selection }
    }

    private var selectedTrigger: CleanupRoute.Trigger? {
        nodes.first { $0.id == selection }?.trigger
    }

    @ViewBuilder
    private func slot(_ index: Int) -> some View {
        if index < nodes.count {
            let node = nodes[index]
            RouteNode(node: node, isSelected: node.id == selection) { onSelect(node.id) }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
        } else if index == nodes.count {
            addButton()
        } else {
            Color.clear
        }
    }

    private var hubs: some View {
        VStack(spacing: RouterFlowLayout.hubSpacing) {
            sourceNode
            routerNode
        }
    }

    private var sourceNode: some View {
        Image(systemName: "waveform")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(isFlowing ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
            .frame(width: RouterFlowLayout.hubSize, height: RouterFlowLayout.hubSize)
            .background(Color(nsColor: .controlBackgroundColor), in: .circle)
            .overlay {
                Circle()
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
            }
            .overlay(alignment: .bottomTrailing) {
                if let selectedTrigger {
                    RouteIcon(trigger: selectedTrigger, size: 18)
                        .offset(x: 4, y: 3)
                        .transition(.scale.combined(with: .opacity))
                        .id(selectedTrigger)
                }
            }
            .overlay(alignment: .leading) {
                caption("Voice")
                    .offset(x: RouterFlowLayout.hubSize + 10)
            }
    }

    private var routerNode: some View {
        Image(systemName: "arrow.triangle.branch")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(180))
            .frame(width: RouterFlowLayout.hubSize, height: RouterFlowLayout.hubSize)
            .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 11))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
            }
            .overlay(alignment: .leading) {
                caption(routerCaption)
                    .offset(x: RouterFlowLayout.hubSize + 10)
            }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .fixedSize()
    }
}

#Preview {
    let ghostty = CleanupRoute.ID(UUID())
    RouterFlowChart(
        nodes: [
            RouterFlowNode(id: .route(ghostty), trigger: .app(MacApp(bundleID: "com.mitchellh.ghostty", name: "Ghostty")), style: .preset(.aiPrompt)),
            RouterFlowNode(id: .route(CleanupRoute.ID(UUID())), trigger: .app(MacApp(bundleID: "com.apple.dt.Xcode", name: "Xcode")), style: .custom),
            RouterFlowNode(id: .fallback, trigger: nil, style: .preset(.cleanUp)),
        ],
        selection: .route(ghostty),
        routerCaption: "Cloud Model",
        isFlowing: true,
        onSelect: { _ in }
    ) {
        RouteAddButton(isPresented: false) {}
    }
    .frame(width: 440)
    .padding()
}
