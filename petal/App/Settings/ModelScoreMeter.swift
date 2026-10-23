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
            case .speed: "bolt.fill"
            case .quality: "sparkle"
            }
        }
    }

    let kind: Kind
    let score: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: kind.symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            ZStack {
                bars(activeCount: 5)
                    .foregroundStyle(.quaternary)
                bars(activeCount: score)
                    .foregroundStyle(.primary)
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
