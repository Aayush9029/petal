import AppFeature
import SwiftUI
import UI

struct MenuBarStatusWaveform: View {
    private static let bars = 69
    private static let rows = 17

    let viewModel: MenuBarContentViewModel

    @State private var simulation = GameOfLifeSimulation(columns: Self.bars, rows: Self.rows)

    var body: some View {
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
