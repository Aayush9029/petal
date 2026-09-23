import Assets
import Shared
import SwiftUI
import UI

struct ModelOptionCard: View {
    let option: ModelOption
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovering = false

    // MARK: - Computed

    private var checkmarkIcon: String {
        isSelected ? "checkmark.circle.fill" : "circle"
    }

    private var borderColor: Color {
        isSelected ? Color.white.opacity(0.6) : Color.white.opacity(0.15)
    }

    private var borderWidth: CGFloat {
        isSelected ? 2 : 1
    }

    // MARK: - Body

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                ModelInfoRow(option: option)

                Spacer(minLength: 8)

                Image(systemName: checkmarkIcon)
                    .font(.title3)
                    .foregroundStyle(isSelected ? .primary : .tertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(.white)
            .background(.black, in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.2), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Previews

#Preview("Selected") {
    ModelOptionCard(option: .mini3b8bit, isSelected: true) {}
        .padding()
        .preferredColorScheme(.dark)
}

#Preview("Unselected") {
    ModelOptionCard(option: .mini3b8bit, isSelected: false) {}
        .padding()
        .preferredColorScheme(.dark)
}
