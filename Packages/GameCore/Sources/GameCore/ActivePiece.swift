// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

public struct ActivePiece: Sendable, Equatable {
    public var id: JunkID
    public var rot: Int
    public var x: Int
    public var y: Int

    public init(id: JunkID, rot: Int = 0, x: Int, y: Int) {
        self.id = id
        self.rot = rot
        self.x = x
        self.y = y
    }

    public var def: JunkDef { JunkCatalog.def(for: id) }

    public var cells: [(Int, Int)] {
        let shape = def.rotations[rot % def.rotations.count]
        return shape.map { ($0[0] + x, $0[1] + y) }
    }

    public func fits(_ board: Board) -> Bool {
        for (cx, cy) in cells {
            if !board.inBounds(x: cx, y: cy) { return false }
            if board.occupied(x: cx, y: cy) { return false }
        }
        return true
    }

    /// Lowest y this piece can rest at without colliding (ghost-drop target).
    public func landingY(on board: Board) -> Int {
        var probe = self
        while true {
            var next = probe
            next.y += 1
            if !next.fits(board) { return probe.y }
            probe = next
        }
    }
}
