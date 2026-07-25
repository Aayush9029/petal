import SwiftUI

/// The popup is a panel, not an `NSMenu`, so the hover highlight has to be drawn rather than inherited.
struct PopupMenuRow: View {
    let title: String
    var systemImage: String?
    var shortcut: String?
    var isDestructive = false
    var isEnabled = true
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 16)
                }
                Text(title)
                Spacer(minLength: 8)
                if let shortcut {
                    Text(shortcut)
                        .foregroundStyle(isHovering ? .white.opacity(0.7) : Color.secondary)
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovering ? AnyShapeStyle(highlight) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 6))
            .contentShape(.rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .onHover { isHovering = isEnabled && $0 }
    }

    private var foreground: Color {
        if !isEnabled { return .secondary }
        if isHovering { return .white }
        return isDestructive ? .red : .primary
    }

    private var highlight: some ShapeStyle {
        isDestructive ? AnyShapeStyle(Color.red.gradient) : AnyShapeStyle(Color.accentColor.gradient)
    }
}

#Preview {
    VStack(spacing: 1) {
        PopupMenuRow(title: "Start Recording", systemImage: "mic.fill") {}
        PopupMenuRow(title: "Stop Recording", systemImage: "stop.fill", isDestructive: true) {}
        PopupMenuRow(title: "Petal Settings…", systemImage: "gearshape", shortcut: "⌘,") {}
        PopupMenuRow(title: "Check for Updates…", systemImage: "arrow.triangle.2.circlepath", isEnabled: false) {}
    }
    .padding(8)
    .frame(width: 312)
}
