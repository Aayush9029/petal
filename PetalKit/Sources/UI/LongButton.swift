import SwiftUI

public enum LongButtonVariant {
    case primary
    case secondary
    case destructive
    case custom(backgroundColor: Color, textColor: Color)

    var backgroundColor: Color {
        switch self {
        case .primary: .black
        case .secondary: .primary.opacity(0.25)
        case .destructive: .red
        case .custom(let bg, _): bg
        }
    }

    var textColor: Color {
        switch self {
        case .primary: .white
        case .secondary: .primary
        case .destructive: .white
        case .custom(_, let text): text
        }
    }
}

public struct LongButton: View {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    let text: String
    let symbol: String?
    let variant: LongButtonVariant
    let luminous: Bool
    let action: () -> Void

    public init(
        _ text: String,
        symbol: String? = nil,
        variant: LongButtonVariant = .primary,
        luminous: Bool = false,
        action: @escaping () -> Void
    ) {
        self.text = text
        self.symbol = symbol
        self.variant = variant
        self.luminous = luminous
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            buttonContent
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var buttonContent: some View {
        Group {
            if let symbol {
                Label(text, systemImage: symbol)
            } else {
                Text(text)
            }
        }
        .foregroundColor(variant.textColor)
        .font(.title3.weight(.medium))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background { buttonBackground }
        .opacity(1)
        .overlay {
            if luminous {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.clear)
                    .runningBorder(
                        radius: 12,
                        lineWidth: 1,
                        animated: true,
                        duration: 1.5,
                        colors: [.white.opacity(0.0), .white.opacity(0.7), .white.opacity(0.0)]
                    )
                    .opacity(isHovering ? 1 : 0)
            }
        }
        .contentShape(.rect(cornerRadius: 12))
    }

    @ViewBuilder
    private var buttonBackground: some View {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: 12)
                .fill(variant.backgroundColor.opacity(0.8))
                .glassEffect(in: .rect(cornerRadius: 12))
        } else {
            variant.backgroundColor
                .clipShape(.rect(cornerRadius: 12))
        }
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 16) {
        LongButton("Primary", variant: .primary) {}
        LongButton("Luminous", variant: .primary, luminous: true) {}
        LongButton("Secondary", variant: .secondary) {}
        LongButton("Destructive", variant: .destructive) {}
        LongButton("With Symbol", symbol: "star.fill", variant: .primary) {}
        LongButton("Disabled", variant: .primary) {}
            .disabled(true)
    }
    .padding()
    .frame(width: 300)
    .preferredColorScheme(.dark)
}
#endif
