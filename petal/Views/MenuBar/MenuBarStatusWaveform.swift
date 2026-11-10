import SwiftUI
import UI

/// Idle draws Conway's Game of Life, a download draws a filling waveform, and the active states draw the pixel waveform.
/// A separate view so audio level updates re-render only the waveform, not the whole popup and its transcript list.
struct MenuBarStatusWaveform: View {
    /// The widest grid that fits the status card, so no column is cut at its edges.
    private static let bars = 69
    private static let rows = 17

    let viewModel: MenuBarContentViewModel

    @State private var simulation = GameOfLifeSimulation(columns: Self.bars, rows: Self.rows)

    var body: some View {
        // The popup's hosting view outlives the panel, so a hidden popup draws nothing and runs no timeline.
        if !viewModel.isPopupVisible {
            Color.clear
        } else if let download = viewModel.downloadStatus {
            DownloadWaveform(
                progress: download.fraction,
                isPaused: download.isPaused,
                bars: Self.bars,
                rows: Self.rows
            )
        } else {
            switch viewModel.iconState {
            case .idle, .error:
                GameOfLifeView(simulation: simulation)
            case .recording:
                LiveWaveform(
                    level: viewModel.audioLevel,
                    bars: Self.bars,
                    rows: Self.rows,
                    tint: .red,
                    sampleInterval: .milliseconds(66)
                )
            case .working:
                ProcessingWaveform(bars: Self.bars, rows: Self.rows, tint: .accentColor)
            }
        }
    }
}
