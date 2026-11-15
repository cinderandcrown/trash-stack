// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

public struct Cell: Sendable, Equatable {
    public var piece: JunkID
    public var material: Material
    /// Sticky goo — cannot recycle until crushed by the press.
    public var sticky: Bool
    public var hazard: HazardKind?

    public init(
        piece: JunkID,
        material: Material,
        sticky: Bool = false,
        hazard: HazardKind? = nil
    ) {
        self.piece = piece
        self.material = material
        self.sticky = sticky
        self.hazard = hazard
    }
}

public struct Board: Sendable, Equatable {
    public let config: BoardConfig
    /// Row-major, y=0 is top (hidden + visible).
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

    /// Crush / remove specific cells (press slam or recycle).
    public mutating func clearCells(_ coords: [(Int, Int)]) {
        for (x, y) in coords {
            self[x, y] = nil
        }
    }

    /// Bottom `count` visible rows (absolute board y indices).
    public func bottomRowIndices(count: Int) -> [Int] {
        let last = config.rows - 1
        let first = max(config.hiddenRows, config.rows - count)
        return Array(first...last)
    }
}
