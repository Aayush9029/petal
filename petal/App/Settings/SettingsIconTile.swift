import SwiftUI

struct SettingsIconTile: View {
    let symbol: String
    let fill: Color
    var size: CGFloat = 24
    var isActive = true

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(isActive ? AnyShapeStyle(fill.gradient) : AnyShapeStyle(Color.secondary.opacity(0.18)))
            Image(systemName: symbol)
                .symbolVariant(.fill)
                .font(.system(size: size * 0.52, weight: .semibold))
                .foregroundStyle(isActive ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
        }
        .frame(width: size, height: size)
        .overlay {
            if contrast == .increased {
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .strokeBorder(.primary.opacity(0.5), lineWidth: 1)
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    HStack {
        SettingsIconTile(symbol: "mic", fill: .pink)
        SettingsIconTile(symbol: "scissors", fill: .orange, size: 30)
        SettingsIconTile(symbol: "hare", fill: .green, size: 30, isActive: false)
    }
    .padding()
}
