import SwiftUI

/// The empty last branch of the router. It opens the add popover.
struct RouteAddButton: View {
    let isPresented: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label("Add App or Website", systemImage: "plus")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isHovering || isPresented ? .primary : .secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.primary.opacity(isHovering || isPresented ? 0.04 : 0))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
                .contentShape(.rect(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .frame(height: RouterFlowLayout.nodeHeight)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.14), value: isHovering)
    }
}

#Preview {
    VStack {
        RouteAddButton(isPresented: false) {}
        RouteAddButton(isPresented: true) {}
    }
    .frame(width: 260)
    .padding()
}
