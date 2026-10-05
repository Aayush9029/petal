import SwiftUI
import UI

/// Idle draws Conway's Game of Life; the active states draw the pixel waveform.
/// A separate view so audio level updates re-render only the waveform, not the whole popup and its transcript list.
struct MenuBarStatusWaveform: View {
    let viewModel: MenuBarContentViewModel

    var body: some View {
        switch viewModel.iconState {
        case .idle, .error:
            GameOfLifeView(tint: .accentColor, isPaused: !viewModel.isPopupVisible)
        case .recording:
            LiveWaveform(
                level: viewModel.audioLevel,
                bars: 72,
                rows: 17,
                tint: .red,
                sampleInterval: .milliseconds(66)
            )
        case .working:
            ProcessingWaveform(bars: 72, rows: 17, tint: .accentColor)
        }
    }
}
