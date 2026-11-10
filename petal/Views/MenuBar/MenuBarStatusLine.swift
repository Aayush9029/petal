import SwiftUI

/// A separate view, so download progress re-renders this line and not the whole popup.
struct MenuBarStatusLine: View {
    let viewModel: MenuBarContentViewModel

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Text(viewModel.statusHeadline)
                .lineLimit(1)
                .monospacedDigit()
            Spacer(minLength: 0)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .help(viewModel.statusHeadline)
    }

    private var tint: Color {
        if let download = viewModel.downloadStatus {
            return download.isPaused ? .yellow : .blue
        }
        return switch viewModel.iconState {
        case .recording: .red
        case .working: .orange
        case .error: .red
        case .idle: .green
        }
    }
}
