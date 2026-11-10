/// Seeds chosen to stay tidy on a short, wide, wrapping board: travellers move in formation and oscillators keep a margin.
enum GameOfLifePattern: CaseIterable {
    case spaceshipConvoy
    case pulsars
    case gliderFleet
    case acorn
    case pentadecathlons
    case soup

    /// Generations before the next pattern replaces this one.
    var lifetime: Int {
        switch self {
        case .spaceshipConvoy: 80
        case .pulsars: 45
        case .gliderFleet: 80
        case .acorn: 150
        case .pentadecathlons: 60
        case .soup: 120
        }
    }

    func board(columns: Int, rows: Int) -> [Bool] {
        var board = Board(columns: columns, rows: rows)
        switch self {
        case .spaceshipConvoy:
            let lanes = [rows / 2 - 6, rows / 2 + 2]
            for (lane, row) in lanes.enumerated() {
                for column in stride(from: 2 + lane * 7, to: columns - 6, by: 14) {
                    board.stamp(Self.lightweightSpaceshipCells, column: column, row: row)
                }
            }
        case .pulsars:
            board.stampRow(Self.pulsarCells, width: 13, height: 13, spacing: 6)
        case .gliderFleet:
            for column in stride(from: 1, to: columns - 4, by: 8) {
                board.stamp(Self.gliderCells, column: column, row: (column / 8).isMultiple(of: 2) ? 2 : rows / 2 + 2)
            }
        case .acorn:
            board.stamp(Self.acornCells, column: (columns - 7) / 2, row: (rows - 3) / 2)
        case .pentadecathlons:
            board.stampRow(Self.pentadecathlonCells, width: 10, height: 3, spacing: 12)
        case .soup:
            let width = min(40, columns - 4), height = min(11, rows - 2)
            for row in 0 ..< height {
                for column in 0 ..< width where Double.random(in: 0 ..< 1) < 0.36 {
                    board.set(column: (columns - width) / 2 + column, row: (rows - height) / 2 + row)
                }
            }
        }
        return board.cells
    }

    private struct Board {
        let columns: Int
        let rows: Int
        var cells: [Bool]

        init(columns: Int, rows: Int) {
            self.columns = columns
            self.rows = rows
            cells = Array(repeating: false, count: columns * rows)
        }

        mutating func set(column: Int, row: Int) {
            guard column >= 0, column < columns, row >= 0, row < rows else { return }
            cells[row * columns + column] = true
        }

        mutating func stamp(_ shape: [(Int, Int)], column: Int, row: Int) {
            for (x, y) in shape { set(column: column + x, row: row + y) }
        }

        /// Centers as many copies as fit in one row.
        mutating func stampRow(_ shape: [(Int, Int)], width: Int, height: Int, spacing: Int) {
            let count = max(1, (columns + spacing) / (width + spacing))
            let total = count * width + (count - 1) * spacing
            for copy in 0 ..< count {
                stamp(shape, column: (columns - total) / 2 + copy * (width + spacing), row: (rows - height) / 2)
            }
        }
    }

    private static let gliderCells: [(Int, Int)] = [(1, 0), (2, 1), (0, 2), (1, 2), (2, 2)]

    private static let lightweightSpaceshipCells: [(Int, Int)] = [
        (0, 0), (3, 0), (4, 1), (0, 2), (4, 2), (1, 3), (2, 3), (3, 3), (4, 3),
    ]

    private static let acornCells: [(Int, Int)] = [(1, 0), (3, 1), (0, 2), (1, 2), (4, 2), (5, 2), (6, 2)]

    private static let pentadecathlonCells: [(Int, Int)] = [
        (2, 0), (7, 0),
        (0, 1), (1, 1), (3, 1), (4, 1), (5, 1), (6, 1), (8, 1), (9, 1),
        (2, 2), (7, 2),
    ]

    private static let pulsarCells: [(Int, Int)] = [
        (2, 0), (3, 0), (4, 0), (8, 0), (9, 0), (10, 0),
        (0, 2), (5, 2), (7, 2), (12, 2), (0, 3), (5, 3), (7, 3), (12, 3),
        (0, 4), (5, 4), (7, 4), (12, 4),
        (2, 5), (3, 5), (4, 5), (8, 5), (9, 5), (10, 5),
        (2, 7), (3, 7), (4, 7), (8, 7), (9, 7), (10, 7),
        (0, 8), (5, 8), (7, 8), (12, 8), (0, 9), (5, 9), (7, 9), (12, 9),
        (0, 10), (5, 10), (7, 10), (12, 10),
        (2, 12), (3, 12), (4, 12), (8, 12), (9, 12), (10, 12),
    ]
}
