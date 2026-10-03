import Shared
import SwiftUI

struct PromptVariableChip: View {
    let variable: CloudPromptVariable
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label(variable.title, systemImage: variable.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .lineLimit(1)
                .padding(.horizontal, 9)
                .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                .background(Color.accentColor.opacity(isHovering ? 0.18 : 0.1), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("\(variable.source). Inserts \(variable.token), for example “\(variable.example)”.")
        .accessibilityLabel("Insert \(variable.title)")
    }
}

#Preview {
    HStack {
        ForEach(CloudPromptVariable.allCases) { PromptVariableChip(variable: $0) {} }
    }
    .padding()
}
