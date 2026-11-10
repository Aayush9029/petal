import SwiftUI

/// An idle-state easter egg: Conway's Game of Life on the same pixel grid as the waveforms.
public struct GameOfLifeView: View {
    private let simulation: GameOfLifeSimulation
    private let tint: Color
    private let isPaused: Bool
    private let metrics: WaveformMetrics

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let opacitySteps = 8

    /// The host owns `simulation`, so the board continues where it stopped when this view returns.
    public init(simulation: GameOfLifeSimulation, tint: Color = .accentColor, isPaused: Bool = false) {
        self.simulation = simulation
        self.tint = tint
        self.isPaused = isPaused
        metrics = .standard
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: isPaused || reduceMotion)) { timeline in
            Canvas { context, size in
                if reduceMotion {
                    simulation.settle()
                } else {
                    simulation.advance(to: timeline.date)
                }
                draw(in: context, size: size)
            }
        }
        .frame(
            width: metrics.width(bars: simulation.columns),
            height: metrics.height(rows: simulation.rows)
        )
        .accessibilityHidden(true)
    }

    /// One path for each opacity step keeps a frame to a few fills, whatever the population.
    private func draw(in context: GraphicsContext, size: CGSize) {
        let columns = simulation.columns
        let originX = (size.width - metrics.width(bars: columns)) / 2
        let originY = (size.height - metrics.height(rows: simulation.rows)) / 2
        let cellSize = CGSize(width: metrics.cell, height: metrics.cell)
        let corner = CGSize(width: metrics.corner, height: metrics.corner)
        var paths = Array(repeating: Path(), count: Self.opacitySteps)

        for (index, level) in simulation.levels.enumerated() where level > 0.04 {
            let step = min(Self.opacitySteps - 1, Int(level * Float(Self.opacitySteps)))
            let origin = CGPoint(
                x: originX + CGFloat(index % columns) * metrics.pitchX,
                y: originY + CGFloat(index / columns) * metrics.pitchY
            )
            paths[step].addRoundedRect(in: CGRect(origin: origin, size: cellSize), cornerSize: corner)
        }

        for (step, path) in paths.enumerated() where !path.isEmpty {
            let opacity = Double(step + 1) / Double(Self.opacitySteps)
            context.fill(path, with: .color(tint.opacity(opacity)))
        }
    }
}

#if DEBUG
#Preview("Game of Life") {
    GameOfLifeView(simulation: GameOfLifeSimulation())
        .frame(width: 276, height: 68)
        .background(.black)
}
#endif
