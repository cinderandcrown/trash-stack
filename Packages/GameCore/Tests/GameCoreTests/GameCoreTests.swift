// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import XCTest
@testable import GameCore

final class GameCoreTests: XCTestCase {
    func testBoardIsEightByFifteenVisible() {
        let c = BoardConfig.dumpster
        XCTAssertEqual(c.cols, 8)
        XCTAssertEqual(c.visibleRows, 15)
        XCTAssertEqual(c.rows, 17)
    }

    func testBagIsDeterministic() {
        var a = RNGBag(seed: 42)
        var b = RNGBag(seed: 42)
        let seqA = (0..<16).map { _ in a.next() }
        let seqB = (0..<16).map { _ in b.next() }
        XCTAssertEqual(seqA, seqB)
        XCTAssertEqual(Set(seqA.prefix(8)).count, JunkID.allCases.count)
    }

    func testScoringCrush() {
        let s = Scoring.crushScore(lines: 3, level: 2, combo: 1, backToBack: true)
        XCTAssertGreaterThan(s, 0)
    }

    func testEngineSpawnsAndHardDrops() {
        var eng = GameEngine(seed: 7)
        XCTAssertNotNil(eng.state.active)
        eng.hardDrop()
        XCTAssertGreaterThanOrEqual(eng.state.score, 0)
        // After a hard drop the piece locks and a new one usually spawns (unless topped out).
        XCTAssertTrue(eng.state.active != nil || eng.state.over)
    }

    func testRecycleFindsGroups() {
        var board = Board()
        for x in 0..<3 {
            board[x, board.config.rows - 1] = Cell(piece: .can, material: .metal)
        }
        let groups = RecycleMatcher.findGroups(on: board)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].cells.count, 3)
    }

    func testEconomyJSONLoadsAndOddsSum() throws {
        let eco = try ConfigLoader.economy()
        XCTAssertEqual(eco.board.cols, 8)
        XCTAssertEqual(eco.soft.startAmount, 80)
        try EconomyMath.validateChests(eco)
        try EconomyMath.assertOfferCaps(eco.oneTimeOffer)
        XCTAssertTrue(eco.compliance.noPurchaseNagging)
        XCTAssertEqual(eco.ads.interstitialEveryNOvers, 3)
        XCTAssertFalse(eco.ads.bannersInPlay)
    }

    func testSeasonPaybackAndShape() throws {
        let season = try ConfigLoader.activeSeason()
        XCTAssertEqual(season.name, "Neon Dumpster")
        XCTAssertEqual(season.tiers, 100)
        try EconomyMath.assertSeasonShape(season)
        let pay = EconomyMath.premiumPayback(season)
        XCTAssertTrue(pay.paysBack)
        XCTAssertEqual(season.bundle.tierSkip, 25)
        XCTAssertTrue(season.tierBuy.neverPushed)
    }

    func testOfferFrequencyCaps() throws {
        let eco = try ConfigLoader.economy()
        let o = eco.oneTimeOffer
        XCTAssertFalse(EconomyMath.canSurfaceOffer(context: "launch", sessionSurfaces: 0, daySurfaces: 0, dismissedDay: nil, dayKey: "2026-11-15", offer: o).ok)
        XCTAssertFalse(EconomyMath.canSurfaceOffer(context: "after_loss", sessionSurfaces: 0, daySurfaces: 0, dismissedDay: nil, dayKey: "2026-11-15", offer: o).ok)
        XCTAssertTrue(EconomyMath.canSurfaceOffer(context: "after_win", sessionSurfaces: 0, daySurfaces: 0, dismissedDay: nil, dayKey: "2026-11-15", offer: o).ok)
        XCTAssertFalse(EconomyMath.canSurfaceOffer(context: "after_win", sessionSurfaces: 1, daySurfaces: 1, dismissedDay: nil, dayKey: "2026-11-15", offer: o).ok)
        XCTAssertFalse(EconomyMath.canSurfaceOffer(context: "after_win", sessionSurfaces: 0, daySurfaces: 0, dismissedDay: "2026-11-15", dayKey: "2026-11-15", offer: o).ok)
        XCTAssertTrue(EconomyMath.canSurfaceOffer(context: "shop", sessionSurfaces: 1, daySurfaces: 1, dismissedDay: "2026-11-15", dayKey: "2026-11-15", offer: o).ok)
    }

    func testLoginStreakEscalates() throws {
        let eco = try ConfigLoader.economy()
        let d1 = EconomyMath.loginStreakScrap(day: 1, cap: eco.loginStreak.capScrap)
        let d14 = EconomyMath.loginStreakScrap(day: 14, cap: eco.loginStreak.capScrap)
        XCTAssertEqual(d1, 5)
        XCTAssertGreaterThan(d14, d1)
        XCTAssertEqual(EconomyMath.loginStreakScrap(day: 999, cap: 120), 120)
    }

    func testGemSpeedup() throws {
        let eco = try ConfigLoader.economy()
        XCTAssertEqual(EconomyMath.gemsForSpeedup(remainingMs: 0, speedup: eco.speedup), 0)
        XCTAssertEqual(EconomyMath.gemsForSpeedup(remainingMs: 1000, speedup: eco.speedup), 1)
    }

    func testShotScenariosAreDistinct() {
        var recycle = GameEngine(seed: 1)
        recycle.applyShotScenario("recycle")
        var revive = GameEngine(seed: 1)
        revive.applyShotScenario("revive")
        XCTAssertFalse(recycle.state.over)
        XCTAssertTrue(revive.state.over)
        XCTAssertNotEqual(recycle.state.score, revive.state.score)
        let recycleFilled = (0..<recycle.state.board.config.cols).filter { recycle.state.board[$0, recycle.state.board.config.rows - 1] != nil }.count
        XCTAssertGreaterThanOrEqual(recycleFilled, 3)
    }
}
