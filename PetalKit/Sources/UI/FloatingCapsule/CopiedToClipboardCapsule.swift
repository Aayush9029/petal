import SwiftUI

struct CopiedToClipboardCapsule: View {
    let blur: CGFloat

    @State private var showsCheckmark = false

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                if showsCheckmark {
                    DottedStatusGlyph(kind: .checkmark, tint: .green)
                        .transition(.opacity.combined(with: .scale(scale: 0.72)))
                } else {
                    DottedStatusGlyph(kind: .clipboard, tint: .green)
                        .transition(.opacity.combined(with: .scale(scale: 1.12)))
                }
            }
            .frame(width: 16, height: 16)

            Text("Copied to clipboard")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .floatingCapsuleChrome(blur: blur)
        .animation(.smooth(duration: 0.24), value: showsCheckmark)
        .task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            showsCheckmark = true
        }
    }
}
