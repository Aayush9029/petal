import SwiftUI

struct ModelScoreMeter: View {
    enum Kind: Equatable {
        case speed
        case quality

        var title: String {
            switch self {
            case .speed: "Speed"
            case .quality: "Intelligence"
            }
        }

        var symbol: String {
            switch self {
            case .speed: "hare.fill"
            case .quality: "sparkle"
            }
        }

        var fill: AnyShapeStyle {
            switch self {
            case .speed:
                AnyShapeStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .leading, endPoint: .trailing))
            case .quality:
                AnyShapeStyle(LinearGradient(
                    colors: [
                        Color(red: 1, green: 0.62, blue: 0.22),
                        Color(red: 1, green: 0.25, blue: 0.48),
                        Color(red: 0.73, green: 0.38, blue: 0.95),
                        Color(red: 0.25, green: 0.68, blue: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
            }
        }
    }

    let kind: Kind
    let score: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: kind.symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(kind.fill)
            ZStack {
                bars(activeCount: 5)
                    .foregroundStyle(Color.secondary.opacity(0.22))
                Rectangle()
                    .fill(kind.fill)
                    .mask { bars(activeCount: score) }
            }
            .frame(width: 34, height: 10)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.title)
        .accessibilityValue("\(score) out of 5")
        .help("\(kind.title): \(score) out of 5")
    }

    private func bars(activeCount: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(1 ... 5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .opacity(index <= activeCount ? 1 : 0)
                    .frame(width: 5, height: 10)
            }
        }
    }
}

#Preview {
    VStack(alignment: .leading) {
        ModelScoreMeter(kind: .speed, score: 4)
        ModelScoreMeter(kind: .quality, score: 2)
    }
    .padding()
}
