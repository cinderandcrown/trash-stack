// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import Foundation

/// Labeled bot opponent for TRASH TALK when matchmaking times out / GC is offline.
/// Plays the same seed and emits junk using the same rules as a human rival.
public struct TrashTalkBot: Sendable {
    public private(set) var engine: GameEngine
    public private(set) var junkSent: Int = 0
    private var thinkAcc: Double = 0
    private let thinkInterval: Double

    public init(seed: UInt64, thinkInterval: Double = 0.55) {
        engine = GameEngine(seed: seed)
        self.thinkInterval = thinkInterval
    }

    public mutating func reset(seed: UInt64) {
        engine.reset(seed: seed)
        junkSent = 0
        thinkAcc = 0
    }

    /// Apply incoming junk from the human rival.
    public mutating func receiveJunk(rows: Int) {
        engine.queueJunk(rows: rows)
    }

    /// Advance bot; returns junk rows to send to the human (already rule-applied).
    public mutating func tick(dt: Double) -> Int {
        guard !engine.state.over else { return 0 }
        _ = engine.tickJunkWarning(dt: dt)
        thinkAcc += dt
        var outbound = 0
        // Soft gravity
        if thinkAcc >= thinkInterval {
            thinkAcc = 0
            outbound += stepOnce()
        }
        return outbound
    }

    private mutating func stepOnce() -> Int {
        let eventsBefore = engine.events.count
        // Simple heuristic: move toward a near-miss column, else random, then soft/hard.
        if let active = engine.state.active {
            let targetX = pickColumn(for: active)
            if active.x < targetX { _ = engine.tryMove(dx: 1, dy: 0) }
            else if active.x > targetX { _ = engine.tryMove(dx: -1, dy: 0) }
            else if Bool.random() { _ = engine.tryRotate() }
            if Int.random(in: 0...4) == 0 {
                engine.hardDrop()
            } else {
                _ = engine.softDrop()
            }
        } else {
            _ = engine.softDrop()
        }
        let newEvents = Array(engine.events.suffix(max(0, engine.events.count - eventsBefore)))
        var junk = 0
        for e in newEvents {
            if case .recycled(let groups, _, _, _, _, _) = e {
                let rows = TrashTalkRules.junkRows(clears: groups, combo: max(1, engine.state.combo))
                junk += rows
                junkSent += rows
            }
        }
        _ = engine.drainEvents()
        return junk
    }

    private func pickColumn(for piece: ActivePiece) -> Int {
        let cols = engine.state.board.config.cols
        // Prefer the lowest stack.
        var best = piece.x
        var bestH = Int.max
        for x in 0..<cols {
            var h = 0
            for y in 0..<engine.state.board.config.rows {
                if engine.state.board[x, y] != nil { h += 1 }
            }
            if h < bestH {
                bestH = h
                best = x
            }
        }
        return best
    }
}
