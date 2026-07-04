import Combine
import SwiftUI

/// An idle-state easter egg: Conway's Game of Life, rendered in the same pixel
/// style as the waveform. It auto-cycles through classic patterns (glider gun,
/// pulsar, spaceship, random soup…), letting each run for a while before
/// reseeding the next. Cells ease in and out so births and deaths look smooth.
public struct GameOfLifeView: View {
    var columns: Int = 64
    var rows: Int = 15
    var tint: Color = .accentColor

    @State private var cells: [Bool]
    @State private var display: [Double]
    @State private var tick = 0
    @State private var stepsSincePattern = 0
    @State private var patternIndex = 0
    @State private var seeded = false

    private let stepEvery = 3          // simulate ~6.7 generations/sec at 20Hz
    private let patternLifetime = 80   // ~12s before moving to the next pattern

    private let ticker = Timer.publish(every: 1.0 / 20.0, on: .main, in: .common).autoconnect()

    public init(columns: Int = 64, rows: Int = 15, tint: Color = .accentColor) {
        self.columns = columns
        self.rows = rows
        self.tint = tint
        _cells = State(initialValue: Array(repeating: false, count: columns * rows))
        _display = State(initialValue: Array(repeating: 0, count: columns * rows))
    }

    public var body: some View {
        GeometryReader { geo in
            let layout = layout(for: geo.size)
            Canvas { context, _ in
                for row in 0..<rows {
                    for col in 0..<columns {
                        let value = display[row * columns + col]
                        guard value > 0.02 else { continue }
                        let rect = CGRect(
                            x: layout.originX + CGFloat(col) * layout.pitch + (layout.pitch - layout.dot) / 2,
                            y: layout.originY + CGFloat(row) * layout.pitch + (layout.pitch - layout.dot) / 2,
                            width: layout.dot,
                            height: layout.dot
                        )
                        context.fill(
                            Path(roundedRect: rect, cornerRadius: layout.dot * 0.3),
                            with: .color(tint.opacity(value))
                        )
                    }
                }
            }
        }
        .onAppear {
            if !seeded { reseed(); seeded = true }
        }
        .onReceive(ticker) { _ in advance() }
    }

    // MARK: - Simulation

    private func advance() {
        tick &+= 1
        if tick % stepEvery == 0 {
            step()
            stepsSincePattern += 1
            if stepsSincePattern >= patternLifetime || cells.allSatisfy({ !$0 }) {
                reseed()
            }
        }
        // Ease each cell toward its live/dead target for smooth fades.
        display = (0..<display.count).map { i in
            let target: Double = cells[i] ? 1 : 0
            return display[i] + (target - display[i]) * 0.32
        }
    }

    private func step() {
        var next = cells
        for row in 0..<rows {
            for col in 0..<columns {
                let n = neighbours(col, row)
                let alive = cells[row * columns + col]
                next[row * columns + col] = alive ? (n == 2 || n == 3) : (n == 3)
            }
        }
        cells = next
    }

    /// Bounded (non-wrapping) neighbour count — movers fly off the edge and the
    /// board clears, which triggers the next pattern.
    private func neighbours(_ col: Int, _ row: Int) -> Int {
        var count = 0
        for dy in -1...1 {
            for dx in -1...1 where !(dx == 0 && dy == 0) {
                let c = col + dx, r = row + dy
                if c >= 0, c < columns, r >= 0, r < rows, cells[r * columns + c] {
                    count += 1
                }
            }
        }
        return count
    }

    private func reseed() {
        var board = Array(repeating: false, count: columns * rows)
        Self.patterns[patternIndex % Self.patterns.count](&board, columns, rows)
        cells = board
        stepsSincePattern = 0
        patternIndex += 1
    }

    // MARK: - Layout

    private struct Layout {
        let pitch: CGFloat
        let dot: CGFloat
        let originX: CGFloat
        let originY: CGFloat
    }

    private func layout(for size: CGSize) -> Layout {
        let pitch = min(size.width / CGFloat(columns), size.height / CGFloat(rows))
        return Layout(
            pitch: pitch,
            dot: pitch * 0.82,
            originX: (size.width - pitch * CGFloat(columns)) / 2,
            originY: (size.height - pitch * CGFloat(rows)) / 2
        )
    }

    // MARK: - Seeding helpers (operate on a fresh board)

    private static func set(_ board: inout [Bool], _ cols: Int, _ rows: Int, _ col: Int, _ row: Int) {
        guard col >= 0, col < cols, row >= 0, row < rows else { return }
        board[row * cols + col] = true
    }

    private static func stampCentered(_ board: inout [Bool], _ cols: Int, _ rows: Int, _ coords: [(Int, Int)]) {
        let width = (coords.map { $0.0 }.max() ?? 0) + 1
        let height = (coords.map { $0.1 }.max() ?? 0) + 1
        stamp(&board, cols, rows, coords, ox: (cols - width) / 2, oy: (rows - height) / 2)
    }

    private static func stamp(_ board: inout [Bool], _ cols: Int, _ rows: Int, _ coords: [(Int, Int)], ox: Int, oy: Int) {
        for (c, r) in coords { set(&board, cols, rows, ox + c, oy + r) }
    }

    private static func randomSoup(_ board: inout [Bool], _ cols: Int, _ rows: Int) {
        let w = min(34, cols - 4), h = min(11, rows - 2)
        let ox = (cols - w) / 2, oy = (rows - h) / 2
        for r in 0..<h {
            for c in 0..<w where Double.random(in: 0...1) < 0.38 {
                set(&board, cols, rows, ox + c, oy + r)
            }
        }
    }

    /// The cycle of patterns, each applied to a fresh board in order.
    private static let patterns: [(inout [Bool], Int, Int) -> Void] = [
        { stamp(&$0, $1, $2, gosperGun, ox: 2, oy: 2) },
        { stampCentered(&$0, $1, $2, pulsar) },
        { stampCentered(&$0, $1, $2, pentadecathlon) },
        { stamp(&$0, $1, $2, lightweightSpaceship, ox: 3, oy: 5) },
        { randomSoup(&$0, $1, $2) },
    ]

    // MARK: - Pattern data

    private static let gosperGun: [(Int, Int)] = [
        (0, 4), (0, 5), (1, 4), (1, 5),
        (10, 4), (10, 5), (10, 6), (11, 3), (11, 7), (12, 2), (12, 8), (13, 2), (13, 8),
        (14, 5), (15, 3), (15, 7), (16, 4), (16, 5), (16, 6), (17, 5),
        (20, 2), (20, 3), (20, 4), (21, 2), (21, 3), (21, 4), (22, 1), (22, 5),
        (24, 0), (24, 1), (24, 5), (24, 6), (34, 2), (34, 3), (35, 2), (35, 3),
    ]

    private static let pulsar: [(Int, Int)] = [
        (2, 0), (3, 0), (4, 0), (8, 0), (9, 0), (10, 0),
        (0, 2), (5, 2), (7, 2), (12, 2), (0, 3), (5, 3), (7, 3), (12, 3),
        (0, 4), (5, 4), (7, 4), (12, 4),
        (2, 5), (3, 5), (4, 5), (8, 5), (9, 5), (10, 5),
        (2, 7), (3, 7), (4, 7), (8, 7), (9, 7), (10, 7),
        (0, 8), (5, 8), (7, 8), (12, 8), (0, 9), (5, 9), (7, 9), (12, 9),
        (0, 10), (5, 10), (7, 10), (12, 10),
        (2, 12), (3, 12), (4, 12), (8, 12), (9, 12), (10, 12),
    ]

    private static let pentadecathlon: [(Int, Int)] = [
        (2, 0), (7, 0),
        (0, 1), (1, 1), (3, 1), (4, 1), (5, 1), (6, 1), (8, 1), (9, 1),
        (2, 2), (7, 2),
    ]

    private static let lightweightSpaceship: [(Int, Int)] = [
        (0, 0), (3, 0), (4, 1), (0, 2), (4, 2), (1, 3), (2, 3), (3, 3), (4, 3),
    ]
}

#if DEBUG
#Preview("Game of Life") {
    GameOfLifeView()
        .frame(width: 264, height: 68)
        .background(.black)
}
#endif
