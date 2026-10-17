import Shared
import SwiftUI

struct CleanupModelNotReadyWarning: View {
    let model: CleanupModel
    let onSetUp: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("\(model.displayName) is not ready. Until it is, Petal pastes your words here as you said them.")
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            SettingsActionButton(title: "Set Up", tint: .orange, action: onSetUp)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.orange.opacity(0.12), in: .rect(cornerRadius: 8))
    }
}

#Preview {
    CleanupModelNotReadyWarning(model: .cloud) {}
        .padding()
        .frame(width: 520)
}
