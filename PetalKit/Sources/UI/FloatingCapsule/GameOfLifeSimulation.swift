import Foundation

/// Conway's Game of Life on a wrapping board. A reference type, so a frame can advance it without a SwiftUI state write.
@MainActor
public final class GameOfLifeSimulation {
    public let columns: Int
    public let rows: Int

    /// Displayed brightness of each cell, eased toward its live or dead target.
    private(set) var levels: [Float]

    private var cells: [Bool]
    private var ages: [UInt8]
    private var lastFrame: Date?
    private var generationClock: TimeInterval = 0
    private var generationsLeft = 0
    private var clearingTimeLeft: TimeInterval = 0
    private var patternIndex: Int
    private var recentHashes: [Int] = []
    private var stagnantGenerations = 0

    private static let generationInterval: TimeInterval = 0.14
    private static let fadeTimeConstant: TimeInterval = 0.11
    /// The old board fades to empty before the next pattern appears, so two patterns never overlap.
    private static let clearingDuration: TimeInterval = 0.5
    private static let stagnationLimit = 14
    private static let longestFrame: TimeInterval = 0.1

    public init(columns: Int = 69, rows: Int = 17) {
        self.columns = columns
        self.rows = rows
        cells = Array(repeating: false, count: columns * rows)
        ages = Array(repeating: 0, count: columns * rows)
        levels = Array(repeating: 0, count: columns * rows)
        patternIndex = Int.random(in: 0 ..< GameOfLifePattern.allCases.count)
        seedNextPattern()
    }

    /// Advances to `date`. A long gap, such as a hidden popup, counts as one frame so the board does not jump.
    func advance(to date: Date) {
        let elapsed = lastFrame.map { min(max(date.timeIntervalSince($0), 0), Self.longestFrame) } ?? 0
        lastFrame = date
        guard elapsed > 0 else { return }

        if clearingTimeLeft > 0 {
            clearingTimeLeft -= elapsed
            if clearingTimeLeft <= 0 { seedNextPattern() }
        } else {
            generationClock += elapsed
            while generationClock >= Self.generationInterval {
                generationClock -= Self.generationInterval
                step()
            }
        }

        let blend = Float(1 - exp(-elapsed / Self.fadeTimeConstant))
        for index in levels.indices {
            let target: Float = cells[index] ? Self.brightness(age: ages[index]) : 0
            levels[index] += (target - levels[index]) * blend
        }
    }

    /// Shows the current board with no fade, for Reduce Motion.
    func settle() {
        for index in levels.indices {
            levels[index] = cells[index] ? 1 : 0
        }
    }

    private static func brightness(age: UInt8) -> Float {
        max(0.55, 1 - 0.09 * Float(age))
    }

    private func step() {
        var next = cells
        var population = 0
        for row in 0 ..< rows {
            let above = (row + rows - 1) % rows * columns
            let middle = row * columns
            let below = (row + 1) % rows * columns
            for column in 0 ..< columns {
                let left = (column + columns - 1) % columns
                let right = (column + 1) % columns
                var neighbours = 0
                if cells[above + left] { neighbours += 1 }
                if cells[above + column] { neighbours += 1 }
                if cells[above + right] { neighbours += 1 }
                if cells[middle + left] { neighbours += 1 }
                if cells[middle + right] { neighbours += 1 }
                if cells[below + left] { neighbours += 1 }
                if cells[below + column] { neighbours += 1 }
                if cells[below + right] { neighbours += 1 }

                let index = middle + column
                let alive = cells[index] ? (neighbours == 2 || neighbours == 3) : neighbours == 3
                next[index] = alive
                if alive {
                    population += 1
                    ages[index] = cells[index] ? min(ages[index] &+ 1, 200) : 0
                }
            }
        }
        cells = next
        generationsLeft -= 1

        // A still life or a blinker repeats within two generations.
        let hash = cells.hashValue
        stagnantGenerations = recentHashes.contains(hash) ? stagnantGenerations + 1 : 0
        recentHashes.append(hash)
        if recentHashes.count > 2 { recentHashes.removeFirst() }

        if population == 0 || generationsLeft <= 0 || stagnantGenerations >= Self.stagnationLimit {
            beginClearing()
        }
    }

    private func beginClearing() {
        cells = Array(repeating: false, count: columns * rows)
        clearingTimeLeft = Self.clearingDuration
    }

    private func seedNextPattern() {
        let pattern = GameOfLifePattern.allCases[patternIndex % GameOfLifePattern.allCases.count]
        patternIndex += 1
        cells = pattern.board(columns: columns, rows: rows)
        ages = Array(repeating: 0, count: columns * rows)
        generationsLeft = pattern.lifetime
        generationClock = 0
        clearingTimeLeft = 0
        recentHashes = []
        stagnantGenerations = 0
    }
}
