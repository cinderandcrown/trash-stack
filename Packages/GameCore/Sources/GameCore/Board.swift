// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

public struct Cell: Sendable, Equatable {
    public var piece: JunkID
    public var material: Material

    public init(piece: JunkID, material: Material) {
        self.piece = piece
        self.material = material
    }
}

public struct Board: Sendable, Equatable {
    public let config: BoardConfig
    /// Row-major, y=0 is top (hidden+visible).
    public private(set) var cells: [[Cell?]]

    public init(config: BoardConfig = .dumpster) {
        self.config = config
        self.cells = Array(
            repeating: Array(repeating: nil, count: config.cols),
            count: config.rows
        )
    }

    public subscript(x: Int, y: Int) -> Cell? {
        get {
            guard x >= 0, y >= 0, x < config.cols, y < config.rows else { return nil }
            return cells[y][x]
        }
        set {
            guard x >= 0, y >= 0, x < config.cols, y < config.rows else { return }
            cells[y][x] = newValue
        }
    }

    public func inBounds(x: Int, y: Int) -> Bool {
        x >= 0 && y >= 0 && x < config.cols && y < config.rows
    }

    public func occupied(x: Int, y: Int) -> Bool {
        self[x, y] != nil
    }

    public mutating func clearRows(_ rows: [Int]) {
        let unique = Array(Set(rows)).sorted()
        for r in unique.reversed() {
            cells.remove(at: r)
            cells.insert(Array(repeating: nil, count: config.cols), at: 0)
        }
    }

    public func fullRows() -> [Int] {
        (0..<config.rows).filter { y in
            cells[y].allSatisfy { $0 != nil }
        }
    }
}
