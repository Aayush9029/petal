import Assets
import Shared
import SwiftUI

struct CloudProviderIcon: View {
    let provider: CloudProvider
    var size: CGFloat = 28

    var body: some View {
        icon
            .frame(width: size, height: size)
            .clipShape(.rect(cornerRadius: size / 4))
    }

    @ViewBuilder
    private var icon: some View {
        switch provider {
        case .openAI:
            Image.openai.resizable().aspectRatio(contentMode: .fill)
        case .anthropic:
            Image.anthropic.resizable().aspectRatio(contentMode: .fill)
        case .openRouter:
            Image.openRouter.resizable().aspectRatio(contentMode: .fill)
        case .custom:
            Image(systemName: "server.rack")
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.gray.gradient)
        }
    }
}

#Preview {
    HStack {
        ForEach(CloudProvider.allCases) { CloudProviderIcon(provider: $0) }
    }
    .padding()
}
