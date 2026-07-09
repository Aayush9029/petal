import Assets
import Shared
import SwiftUI
import UI

struct CapsuleAppearancePicker: View {
    let selection: FloatingCapsuleBackgroundStyle
    let onSelect: (FloatingCapsuleBackgroundStyle) -> Void
    @State private var hoveredStyle: FloatingCapsuleBackgroundStyle?

    var body: some View {
        HStack(spacing: 12) {
            appearanceOption(.liquidGlass, label: "Glass")
            appearanceOption(.solid, label: "Opaque")
        }
    }

    private func appearanceOption(
        _ style: FloatingCapsuleBackgroundStyle,
        label: String
    ) -> some View {
        Button {
            onSelect(style)
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Image.settingsWallpaper
                        .resizable()
                        .scaledToFill()

                    capsule(for: style, animated: hoveredStyle == style)
                        .padding(.horizontal, 22)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .clipShape(.rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            selection == style ? Color.primary.opacity(0.5) : Color(nsColor: .separatorColor),
                            lineWidth: selection == style ? 3 : 1
                        )
                }

                Text(label)
                    .font(.subheadline.weight(selection == style ? .semibold : .medium))
                    .foregroundStyle(selection == style ? .primary : .secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            withAnimation(.easeOut(duration: 0.16)) {
                hoveredStyle = isHovering ? style : nil
            }
        }
        .accessibilityLabel("\(label) recording bar")
        .accessibilityAddTraits(selection == style ? .isSelected : [])
    }

    @ViewBuilder
    private func capsule(for style: FloatingCapsuleBackgroundStyle, animated: Bool) -> some View {
        let content = ZStack {
            HStack(spacing: 4) {
                ForEach(0 ..< 22, id: \.self) { index in
                    Circle()
                        .fill(.red)
                        .frame(width: 2, height: CGFloat(2 + (index * 7) % 11))
                }
            }
            .opacity(animated ? 0 : 1)

            if animated {
                ProcessingWaveform(bars: 32, rows: 5, tint: .red)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 20)
        .padding(.horizontal, 13)
        .padding(.vertical, 8)

        switch style {
        case .solid:
            content
                .background(Color(nsColor: .windowBackgroundColor), in: .capsule)
                .overlay { Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 1) }
        case .liquidGlass:
            if #available(macOS 26.0, *) {
                content
                    .glassEffect(in: .capsule)
                    .overlay { Capsule().strokeBorder(.white.opacity(0.28), lineWidth: 1) }
            } else {
                content
                    .background(.ultraThinMaterial, in: .capsule)
                    .overlay { Capsule().strokeBorder(.white.opacity(0.28), lineWidth: 1) }
            }
        }
    }
}
