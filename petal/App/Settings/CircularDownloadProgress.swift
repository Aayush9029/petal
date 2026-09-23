import SwiftUI

struct CircularDownloadProgress: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle().stroke(.secondary.opacity(0.24), lineWidth: 3.5)
            Circle()
                .trim(from: 0, to: max(0.03, min(1, fraction)))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 18, height: 18)
        .animation(.linear(duration: 0.15), value: fraction)
    }
}

#Preview {
    HStack {
        CircularDownloadProgress(fraction: 0)
        CircularDownloadProgress(fraction: 0.4)
        CircularDownloadProgress(fraction: 1)
    }
    .padding()
}
