// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

public enum GameEvent: Sendable, Equatable {
    case spawned(JunkID)
    case locked
    case cleared(rows: [Int], score: Int, scrap: Int)
    case recycled(groups: Int, score: Int, scrap: Int)
    case magnetUsed
    case gameOver
    case leveledUp(Int)
}

public struct GameState: Sendable, Equatable {
    public var board: Board
    public var active: ActivePiece?
    public var hold: JunkID?
    public var holdUsed: Bool
    public var queue: [JunkID]
    public var score: Int
    public var lines: Int
    public var level: Int
    public var combo: Int
    public var backToBack: Bool
    public var magnetCharge: Int
    public var over: Bool
    public var runScrap: Int

    public init(config: BoardConfig = .dumpster) {
        board = Board(config: config)
        active = nil
        hold = nil
        holdUsed = false
        queue = []
        score = 0
        lines = 0
        level = 1
        combo = 0
        backToBack = false
        magnetCharge = 0
        over = false
        runScrap = 0
    }
}

/// Pure game rules — no SpriteKit / UIKit.
public struct GameEngine: Sendable {
    public private(set) var state: GameState
    private var bag: RNGBag
    public var events: [GameEvent] = []

    public init(seed: UInt64 = 0xC1A55, config: BoardConfig = .dumpster) {
        state = GameState(config: config)
        bag = RNGBag(seed: seed)
        fillQueue()
        spawn()
    }

    public mutating func reset(seed: UInt64) {
        state = GameState(config: state.board.config)
        bag = RNGBag(seed: seed)
        events = []
        fillQueue()
        spawn()
    }

    /// Clear game-over and respawn for a one-time revive.
    public mutating func revive() {
        state.over = false
        if state.active == nil {
            _ = spawn()
        }
    }

    private mutating func fillQueue() {
        while state.queue.count < 5 {
            state.queue.append(bag.next())
        }
    }

    @discardableResult
    public mutating func spawn() -> Bool {
        fillQueue()
        let id = state.queue.removeFirst()
        fillQueue()
        let piece = ActivePiece(id: id, x: state.board.config.cols / 2 - 1, y: 0)
        if !piece.fits(state.board) {
            state.over = true
            events.append(.gameOver)
            return false
        }
        state.active = piece
        state.holdUsed = false
        events.append(.spawned(id))
        return true
    }

    public mutating func tryMove(dx: Int, dy: Int) -> Bool {
        guard var p = state.active, !state.over else { return false }
        p.x += dx
        p.y += dy
        guard p.fits(state.board) else { return false }
        state.active = p
        return true
    }

    public mutating func tryRotate() -> Bool {
        guard var p = state.active, !state.over else { return false }
        let old = p.rot
        p.rot = (p.rot + 1) % p.def.rotations.count
        if p.fits(state.board) {
            state.active = p
            return true
        }
        // simple wall kicks
        for kick in [-1, 1, -2, 2] {
            var k = p
            k.x += kick
            if k.fits(state.board) {
                state.active = k
                return true
            }
        }
        p.rot = old
        state.active = p
        return false
    }

    public mutating func hardDrop() {
        guard state.active != nil, !state.over else { return }
        while tryMove(dx: 0, dy: 1) {}
        lock()
    }

    public mutating func softDrop() -> Bool {
        tryMove(dx: 0, dy: 1)
    }

    public mutating func lock() {
        guard let p = state.active else { return }
        let def = p.def
        for (x, y) in p.cells {
            state.board[x, y] = Cell(piece: p.id, material: def.material)
        }
        state.active = nil
        events.append(.locked)
        resolveAfterLock()
    }

    private mutating func resolveAfterLock() {
        // Recycle first (signature), then full-row compactor crush.
        let groups = RecycleMatcher.findGroups(on: state.board)
        let didRecycle = !groups.isEmpty
        if didRecycle {
            var cells = 0
            for g in groups {
                cells += g.cells.count
                for (x, y) in g.cells { state.board[x, y] = nil }
            }
            let scrap = Scoring.scrapForRecycle(groups: groups.count, cells: cells)
            let score = cells * 40 * state.level + groups.count * 60
            state.score += score
            state.runScrap += scrap
            state.combo += 1
            state.magnetCharge = min(3, state.magnetCharge + (groups.count >= 2 ? 1 : 0))
            events.append(.recycled(groups: groups.count, score: score, scrap: scrap))
            applyGravity()
        }

        let full = state.board.fullRows().filter { $0 >= state.board.config.hiddenRows }
        if !full.isEmpty {
            let n = full.count
            let leveledBefore = state.level
            let score = Scoring.crushScore(lines: n, level: state.level, combo: state.combo, backToBack: state.backToBack)
            let scrap = Scoring.scrapForClear(lines: n, combo: state.combo, leveled: false)
            state.board.clearRows(full)
            state.score += score
            state.lines += n
            state.runScrap += scrap
            state.combo += 1
            state.backToBack = n >= 3
            state.level = 1 + state.lines / 10
            if state.level > leveledBefore {
                events.append(.leveledUp(state.level))
            }
            events.append(.cleared(rows: full, score: score, scrap: scrap))
        } else if !didRecycle {
            state.combo = 0
            state.backToBack = false
        }

        if !spawn() {
            // game over already flagged
        }
    }

    private mutating func applyGravity() {
        let cols = state.board.config.cols
        let rows = state.board.config.rows
        for x in 0..<cols {
            var stack: [Cell] = []
            for y in (0..<rows).reversed() {
                if let c = state.board[x, y] { stack.append(c) }
            }
            for y in 0..<rows { state.board[x, y] = nil }
            var y = rows - 1
            for c in stack {
                state.board[x, y] = c
                y -= 1
            }
        }
    }

    /// Stash bin — not a classic "hold" lookalike naming in UI; mechanic is stash.
    public mutating func stash() {
        guard let cur = state.active, !state.holdUsed, !state.over else { return }
        state.holdUsed = true
        if let h = state.hold {
            state.hold = cur.id
            let next = ActivePiece(id: h, x: state.board.config.cols / 2 - 1, y: 0)
            if !next.fits(state.board) {
                state.over = true
                events.append(.gameOver)
                return
            }
            state.active = next
        } else {
            state.hold = cur.id
            state.active = nil
            spawn()
        }
    }

    /// Magnet power-up: pull matching material scraps toward the active piece column.
    public mutating func useMagnet() {
        guard state.magnetCharge > 0, let p = state.active, !state.over else { return }
        state.magnetCharge -= 1
        let mat = p.def.material
        let targetX = p.x
        for y in 0..<state.board.config.rows {
            for x in 0..<state.board.config.cols where x != targetX {
                guard let c = state.board[x, y], c.material == mat else { continue }
                if state.board[targetX, y] == nil {
                    state.board[targetX, y] = c
                    state.board[x, y] = nil
                }
            }
        }
        events.append(.magnetUsed)
    }

    /// Autoplay helper for CI smoke: hard-drop repeatedly.
    public mutating func autoplayStep() {
        guard !state.over else { return }
        if Bool.random() { _ = tryRotate() }
        if Bool.random() { _ = tryMove(dx: Bool.random() ? 1 : -1, dy: 0) }
        hardDrop()
    }
}
