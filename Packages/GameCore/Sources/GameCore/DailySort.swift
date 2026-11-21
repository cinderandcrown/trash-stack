// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import Foundation

/// Fixed hand-made Daily Sort board — one logical solution, no timer.
public struct DailySortPuzzle: Sendable {
    public var dayKey: String
    public var title: String
    public var lives: Int
    public var board: [(x: Int, y: Int, cell: Cell)]
    /// Exact tray sequence the player receives (groups of 3).
    public var trayDeals: [[JunkID]]
    /// Forced-move hints as (trayIndex, x, y, rot) for each successful place step.
    public var solution: [DailySortStep]
    public var goal: OrderTicket

    public init(
        dayKey: String,
        title: String,
        lives: Int = 3,
        board: [(Int, Int, Cell)],
        trayDeals: [[JunkID]],
        solution: [DailySortStep],
        goal: OrderTicket
    ) {
        self.dayKey = dayKey
        self.title = title
        self.lives = lives
        self.board = board
        self.trayDeals = trayDeals
        self.solution = solution
        self.goal = goal
    }
}

public struct DailySortStep: Sendable, Equatable {
    public var trayIndex: Int
    public var x: Int
    public var y: Int
    public var rot: Int
    public init(trayIndex: Int, x: Int, y: Int, rot: Int = 0) {
        self.trayIndex = trayIndex
        self.x = x
        self.y = y
        self.rot = rot
    }
}

public enum DailySortCatalog {
    /// Hand-made daily puzzles keyed by UTC day seed. Falls back to a stable starter puzzle.
    public static func puzzle(for date: Date = Date()) -> DailySortPuzzle {
        let key = DailyDumpster.dayKey(for: date)
        return starter(dayKey: key)
    }

    /// Starter Daily Sort: three metal on the floor; place the can to recycle. One forced move.
    public static func starter(dayKey: String) -> DailySortPuzzle {
        let f = BoardConfig.dumpster.rows - 1
        return DailySortPuzzle(
            dayKey: dayKey,
            title: "Morning Sort",
            lives: 3,
            board: [
                (2, f, Cell(piece: .can, material: .metal)),
                (3, f, Cell(piece: .can, material: .metal)),
                (4, f, Cell(piece: .can, material: .metal)),
                (6, f, Cell(piece: .plank, material: .paper)),
            ],
            trayDeals: [[.can, .plank, .bottle]],
            solution: [DailySortStep(trayIndex: 0, x: 1, y: f, rot: 0)],
            goal: OrderTicket(
                id: "daily-sort",
                label: "Recycle 4 metal",
                kind: .recycleMaterial,
                target: 4,
                material: .metal
            )
        )
    }

    /// Next forced move for the current step index, or nil if solved / out of range.
    public static func hint(for puzzle: DailySortPuzzle, stepIndex: Int) -> DailySortStep? {
        guard stepIndex >= 0, stepIndex < puzzle.solution.count else { return nil }
        return puzzle.solution[stepIndex]
    }
}
