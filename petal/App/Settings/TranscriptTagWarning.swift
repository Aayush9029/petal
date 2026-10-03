import SwiftUI

struct TranscriptTagWarning: View {
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("The prompt must mention <transcript>. Until it does, Petal adds a line about it.")
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            SettingsActionButton(title: "Add", tint: .orange, action: onAdd)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.orange.opacity(0.12), in: .rect(cornerRadius: 8))
    }
}

#Preview {
    TranscriptTagWarning {}
        .padding()
        .frame(width: 520)
}
