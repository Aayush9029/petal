import SwiftUI

private let countdownDuration: TimeInterval = 4

struct CancelConfirmationCapsule: View {
    var isActive: Bool

    @State private var progress: CGFloat = 1
    @Environment(\.colorScheme) private var colorScheme

    private var borderColor: Color {
        colorScheme == .dark ? .white : .black
    }

    var body: some View {
        Color.clear
            .floatingCapsuleChrome(blur: 0)
            .overlay {
                HStack(spacing: 6) {
                    Image(systemName: "escape")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    (
                        Text("Cancel recording?  ")
                            + Text("Y").foregroundColor(.red)
                    )
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                }
                .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
            }
            .overlay {
                Capsule()
                    .trim(from: 0, to: progress)
                    .stroke(borderColor.opacity(0.6), lineWidth: 2)
                    .padding(2)
            }
            .onChange(of: isActive) { _, active in
                if active {
                    progress = 1
                    withAnimation(.linear(duration: countdownDuration)) {
                        progress = 0
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.15)) {
                        progress = 0
                    }
                }
            }
            .onAppear {
                if isActive {
                    progress = 1
                    withAnimation(.linear(duration: countdownDuration)) {
                        progress = 0
                    }
                }
            }
    }
}
