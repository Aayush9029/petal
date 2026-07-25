import SwiftUI

struct PermissionCalloutRow: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Spacer(minLength: 8)
            }
            .foregroundStyle(isHovering ? Color.white : .primary)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .background(
                isHovering ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(.quaternary),
                in: .rect(cornerRadius: 8)
            )
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.14), value: isHovering)
        .onHover { isHovering = $0 }
    }
}

#Preview {
    VStack(spacing: 6) {
        PermissionCalloutRow(title: "Allow Microphone Access", systemImage: "mic.fill") {}
        PermissionCalloutRow(title: "Turn On Accessibility", systemImage: "hand.raised.fill") {}
    }
    .padding(8)
    .frame(width: 312)
}
