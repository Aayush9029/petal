import Shared
import SwiftUI

struct CloudProviderPicker: View {
    let selection: CloudProvider
    let onSelect: (CloudProvider) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(CloudProvider.allCases) { provider in
                SelectableCard(isSelected: selection == provider) {
                    onSelect(provider)
                } content: {
                    VStack(spacing: 7) {
                        CloudProviderIcon(provider: provider, size: 30)
                        Text(provider.displayName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .accessibilityLabel(provider.displayName)
            }
        }
    }
}

#Preview {
    @Previewable @State var provider = CloudProvider.openAI
    CloudProviderPicker(selection: provider) { provider = $0 }
        .frame(width: 460)
        .padding()
}
