import Assets
import Shared
import SwiftUI

struct CleanupModelIcon: View {
    let model: CleanupModel
    var size: CGFloat = 28

    var body: some View {
        icon
            .frame(width: size, height: size)
            .clipShape(.rect(cornerRadius: size / 4))
    }

    @ViewBuilder
    private var icon: some View {
        switch model {
        case .off:
            symbol("text.alignleft", fill: .gray)
        case .appleIntelligence:
            Image.appleIntelligence
                .resizable()
                .aspectRatio(contentMode: .fill)
        case .petalW1:
            Image.appIcon
                .resizable()
                .aspectRatio(contentMode: .fill)
        case .cloud:
            symbol("cloud.fill", fill: .blue)
        }
    }

    private func symbol(_ name: String, fill: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: size * 0.46, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(fill.gradient)
    }
}

#Preview {
    HStack {
        ForEach(CleanupModel.allCases) { CleanupModelIcon(model: $0) }
    }
    .padding()
}
