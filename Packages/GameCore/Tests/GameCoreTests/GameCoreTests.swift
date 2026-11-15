// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import XCTest
@testable import GameCore

final class GameCoreTests: XCTestCase {
    func testBoardIsEightByFourteenVisible() {
        let c = BoardConfig.dumpster
        XCTAssertEqual(c.cols, 8)
        XCTAssertEqual(c.visibleRows, 14)
        XCTAssertEqual(c.rows, 16)
    }

    func testBagIsDeterministic() {
        var a = RNGBag(seed: 42)
        var b = RNGBag(seed: 42)
        let seqA = (0..<24).map { _ in a.next() }
        let seqB = (0..<24).map { _ in b.next() }
        XCTAssertEqual(seqA, seqB)
    }

    func testRecycleNeedsFourSameMaterial() {
        var board = Board()
        for x in 0..<3 {
            board[x, board.config.rows - 1] = Cell(piece: .can, material: .metal)
        }
        XCTAssertTrue(RecycleMatcher.findGroups(on: board).isEmpty)
        board[3, board.config.rows - 1] = Cell(piece: .can, material: .metal)
        let groups = RecycleMatcher.findGroups(on: board)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].cells.count, 4)
    }

    func testStickyExcludedFromRecycle() {
        var board = Board()
        for x in 0..<4 {
            board[x, board.config.rows - 1] = Cell(piece: .can, material: .metal, sticky: x == 0)
        }
        // Only 3 non-sticky metal — should not recycle.
        XCTAssertTrue(RecycleMatcher.findGroups(on: board).isEmpty)
    }

    func testPressSlamsBottomRows() {
        var eng = GameEngine(seed: 3)
        eng.applyShotScenario("press")
        eng.fillPressMeter()
        let before = eng.state.score
        XCTAssertTrue(eng.slamPress())
        XCTAssertGreaterThan(eng.state.score, before)
        XCTAssertEqual(eng.state.pressMeter, 0)
    }

    func testSnatchOnce() {
        var eng = GameEngine(seed: 9)
        eng.applyShotScenario("game")
        XCTAssertTrue(eng.state.snatchAvailable)
        XCTAssertTrue(eng.snatchRandom())
        XCTAssertFalse(eng.state.snatchAvailable)
        XCTAssertFalse(eng.snatchRandom())
    }

    func testEngineSpawnsAndHardDrops() {
        var eng = GameEngine(seed: 7)
        XCTAssertNotNil(eng.state.active)
        eng.hardDrop()
        XCTAssertGreaterThanOrEqual(eng.state.score, 0)
        XCTAssertTrue(eng.state.active != nil || eng.state.over)
    }

    func testEconomyJSONLoadsAndOddsSum() throws {
        let eco = try ConfigLoader.economy()
        XCTAssertEqual(eco.board.cols, 8)
        XCTAssertEqual(eco.board.visibleRows, 14)
        XCTAssertEqual(eco.soft.startAmount, 80)
        try EconomyMath.validateChests(eco)
        try EconomyMath.assertOfferCaps(eco.oneTimeOffer)
        XCTAssertTrue(eco.compliance.noPurchaseNagging)
    }

    func testSeasonPaybackAndShape() throws {
        let season = try ConfigLoader.activeSeason()
        XCTAssertEqual(season.name, "Neon Dumpster")
        XCTAssertEqual(season.tiers, 100)
        try EconomyMath.assertSeasonShape(season)
        let pay = EconomyMath.premiumPayback(season)
        XCTAssertTrue(pay.paysBack)
    }

    func testShotScenariosAreDistinct() {
        var recycle = GameEngine(seed: 1)
        recycle.applyShotScenario("recycle")
        var revive = GameEngine(seed: 1)
        revive.applyShotScenario("revive")
        var press = GameEngine(seed: 1)
        press.applyShotScenario("compactor")
        var play = GameEngine(seed: 1)
        play.applyShotScenario("game")
        XCTAssertFalse(recycle.state.over)
        XCTAssertTrue(revive.state.over)
        XCTAssertNotEqual(recycle.state.score, revive.state.score)
        XCTAssertNotEqual(press.state.score, play.state.score)
        XCTAssertEqual(press.state.pressMeter, press.state.pressMeterMax)
        let vis = play.state.board.config.visibleRows
        let hid = play.state.board.config.hiddenRows
        var filled = 0
        for y in hid..<(hid + vis) {
            for x in 0..<play.state.board.config.cols where play.state.board[x, y] != nil {
                filled += 1
            }
        }
        let capacity = play.state.board.config.cols * vis
        XCTAssertGreaterThan(filled, capacity / 8)
        XCTAssertNotNil(play.state.active)
    }

    func testNoForbiddenLetterPieceNames() {
        for id in JunkID.allCases {
            let name = id.rawValue.lowercased()
            XCTAssertFalse(["t", "s", "z", "i", "o"].contains(name))
            XCTAssertFalse(name.contains("tetromino"))
            XCTAssertFalse(name.contains("tetris"))
        }
    }
}
