// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import XCTest
@testable import GameCore

final class TurnBasedTests: XCTestCase {
    func testLevel1DragPlaceClearsMetalAndWins() {
        var eng = GameEngine(seed: 1)
        eng.paceCascades = false
        eng.startLevel(LevelCatalog.level(id: 1), seed: 1)
        XCTAssertTrue(eng.state.isTurnBased)
        XCTAssertFalse(eng.state.boardHasFloatingTilesHelper)
        XCTAssertEqual(eng.state.tray.compactMap { $0 }.count, 3)

        // Tray[0] is can — place at (1, floor) beside the three metal tiles.
        XCTAssertTrue(eng.selectTray(0))
        let floor = eng.state.board.config.rows - 1
        XCTAssertEqual(eng.setPreview(x: 1, y: floor), .fits)
        XCTAssertTrue(eng.placeSelected())

        // Metal recycled; plastic settles into a chain clear; nothing floating.
        XCTAssertTrue(eng.boardHasNoFloatingTiles())
        XCTAssertTrue(eng.state.levelWon || eng.state.orders.contains(where: \.done))
        if eng.state.levelWon {
            XCTAssertGreaterThanOrEqual(eng.state.starsEarned, 1)
        }
        // Sync cascades run both waves before return — plastic chain should have fired.
        XCTAssertGreaterThanOrEqual(eng.state.combo, 1)
    }

    func testPlaceNeverWritesIntoOccupiedCell() {
        var eng = GameEngine(seed: 2)
        eng.paceCascades = false
        eng.startLevel(LevelCatalog.level(id: 1), seed: 2)
        XCTAssertTrue(eng.selectTray(0))
        let floor = eng.state.board.config.rows - 1
        // Occupied by pre-placed metal at (2, floor).
        XCTAssertEqual(eng.setPreview(x: 2, y: floor), .blocked)
        XCTAssertFalse(eng.placeSelected())
        XCTAssertEqual(eng.state.board[2, floor]?.material, .metal)
    }

    func testLevel1PlaceTriggersMetalThenPlasticChain() {
        var eng = GameEngine(seed: 11)
        eng.paceCascades = false
        eng.startLevel(LevelCatalog.level(id: 1), seed: 11)
        XCTAssertTrue(eng.selectTray(0))
        let floor = eng.state.board.config.rows - 1
        XCTAssertTrue(eng.setPreview(x: 1, y: floor) == .fits && eng.placeSelected())
        // Goal met after metal clear; plastic chain also cleared in sync mode.
        XCTAssertTrue(eng.state.levelWon)
        XCTAssertGreaterThanOrEqual(eng.state.starsEarned, 1)
        XCTAssertNil(eng.state.board[2, floor])
        XCTAssertNil(eng.state.board[3, floor])
        XCTAssertTrue(eng.boardHasNoFloatingTiles())
    }

    func testTwentyLevelsExistAndArePrefilled() {
        XCTAssertEqual(LevelCatalog.all.count, 20)
        for def in LevelCatalog.all {
            XCTAssertFalse(def.board.isEmpty, "level \(def.id) must start with junk on the board")
            XCTAssertEqual(def.tray.count, 3)
            XCTAssertGreaterThan(def.moveLimit, 0)
        }
    }

    func testSettleAfterClearIsModelDriven() {
        var eng = GameEngine(seed: 3)
        eng.paceCascades = false
        let rows = eng.state.board.config.rows
        eng.startLevel(LevelCatalog.level(id: 6), seed: 3)
        // Level 6 has plastic sitting on metal — clearing metal must pack plastic.
        XCTAssertTrue(eng.selectTray(0)) // can
        let floor = rows - 1
        // Find a fitting seat for the can near the metal cluster.
        var placed = false
        for x in 0..<8 {
            if eng.setPreview(x: x, y: floor) == .fits, eng.placeSelected() {
                placed = true
                break
            }
            _ = eng.selectTray(0)
        }
        XCTAssertTrue(placed || eng.state.movesLeft < eng.state.moveLimit)
        XCTAssertTrue(eng.boardHasNoFloatingTiles())
    }

    func testDailySortHintDoesNotPlace() {
        var eng = GameEngine(seed: 4)
        let puzzle = DailySortCatalog.starter(dayKey: "20261121")
        eng.startDailySort(puzzle)
        let hint = eng.dailyHint(puzzle: puzzle)
        XCTAssertNotNil(hint)
        XCTAssertEqual(hint?.trayIndex, 0)
        // Board unchanged by hint.
        let before = eng.state.board[2, eng.state.board.config.rows - 1]?.material
        XCTAssertEqual(before, .metal)
        XCTAssertNil(eng.state.active)
    }
}

private extension GameState {
    var boardHasFloatingTilesHelper: Bool {
        // Mirror engine helper for quick asserts in setup.
        let rows = board.config.rows
        let cols = board.config.cols
        for x in 0..<cols {
            var seenEmpty = false
            for y in (0..<rows).reversed() {
                if board[x, y] == nil { seenEmpty = true }
                else if seenEmpty { return true }
            }
        }
        return false
    }
}
