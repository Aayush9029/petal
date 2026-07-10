import SwiftUI

private let countdownDuration: TimeInterval = 4

struct CancelConfirmationCapsule: View {
    @Environment(\.colorScheme) private var colorScheme

    var isActive: Bool

    @State private var progress: CGFloat = 1

    private var countdownStrokeColor: Color {
        colorScheme == .dark ? .white : .black
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "escape")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Cancel recording?")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .padding(.trailing, 4)

            ZStack {
                Circle()
                    .fill(.red)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(countdownStrokeColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Text("Y")
                    .font(.caption2.monospaced().weight(.bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 26, height: 26)
            .accessibilityHidden(true)
        }
        .floatingCapsuleChrome(
            blur: 0,
            contentWidth: 178,
            contentHeight: 28,
            horizontalPadding: 4,
            trailingPadding: 2,
            verticalPadding: 7
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cancel recording? Press Y to confirm")
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
