import Shared
import SwiftUI

struct RouteAddAppTile: View {
    let app: MacApp
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                RouteIcon(trigger: .app(app), size: 36)
                Text(app.name)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .background(Color.primary.opacity(isHovering ? 0.07 : 0), in: .rect(cornerRadius: 9))
            .contentShape(.rect(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.1), value: isHovering)
        .help("Add \(app.name)")
    }
}

#Preview {
    HStack {
        RouteAddAppTile(app: MacApp(bundleID: "com.apple.mail", name: "Mail")) {}
        RouteAddAppTile(app: MacApp(bundleID: "com.apple.Terminal", name: "Terminal")) {}
    }
    .frame(width: 200)
    .padding()
}
