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
        // Build banned tokens from parts so this file never contains the classic falling-block trademark.
        let bannedGame = ["tet", "ris"].joined()
        let bannedShape = ["tetro", "mino"].joined()
        for id in JunkID.allCases {
            let name = id.rawValue.lowercased()
            XCTAssertFalse(["t", "s", "z", "i", "o"].contains(name))
            XCTAssertFalse(name.contains(bannedShape))
            XCTAssertFalse(name.contains(bannedGame))
        }
    }

    func testDailyDumpsterSeedIsUTCDayStable() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        var comps = DateComponents()
        comps.year = 2026; comps.month = 11; comps.day = 15
        let day = cal.date(from: comps)!
        let a = DailyDumpster.seed(for: day)
        let b = DailyDumpster.seed(for: day.addingTimeInterval(3600 * 5))
        XCTAssertEqual(a, b)
        XCTAssertEqual(a, 2026_11_15)
        var eng = GameEngine(seed: 1)
        eng.applyShotScenario("daily")
        XCTAssertFalse(eng.state.over)
        XCTAssertEqual(eng.state.orders.count, 3)
        XCTAssertFalse(eng.materialShareGrid().isEmpty)
    }

    func testDailyShareCardEmojiGrid() {
        let grid: [[Material?]] = [
            [.metal, .glass, nil, .plastic, .paper, .metal, .glass, .plastic],
            [.paper, nil, .metal, .glass, .plastic, nil, .paper, .metal],
        ]
        let card = DailyDumpster.shareCard(dayKey: "20261115", score: 2400, stars: 3, materialGrid: grid)
        XCTAssertTrue(card.contains("Trash Stack Daily Dumpster"))
        XCTAssertTrue(card.contains("Score 2400"))
        XCTAssertTrue(card.contains("★★★"))
        XCTAssertTrue(card.contains("🪙") || card.contains("🫙"))
        XCTAssertTrue(card.contains("#TrashStack"))
    }

    func testStreakRewardsEscalate() {
        XCTAssertEqual(StreakRewards.scrap(forDay: 1), 18)
        XCTAssertGreaterThan(StreakRewards.scrap(forDay: 7), StreakRewards.scrap(forDay: 1))
        XCTAssertEqual(StreakRewards.gems(forDay: 7), 5)
        XCTAssertEqual(ShiftCatalog.levels.count, 6)
        XCTAssertEqual(PlayMode.allCases.count, 3)
    }

    func testHoldSlotAndNearMiss() {
        var eng = GameEngine(seed: 11)
        eng.applyShotScenario("game")
        XCTAssertNil(eng.state.hold)
        eng.stash()
        XCTAssertNotNil(eng.state.hold)
        XCTAssertFalse(eng.isNearOverflow())
        eng.applyShotScenario("revive")
        XCTAssertTrue(eng.isNearOverflow())
    }

    func testPreviewMatchesSpawnedPiece() {
        var eng = GameEngine(seed: 2026_11_15)
        for _ in 0..<40 {
            guard !eng.state.over, eng.state.active != nil else { break }
            let preview = eng.peekNext(2)
            XCTAssertFalse(preview.isEmpty)
            let expected = preview[0]
            eng.hardDrop()
            if eng.state.over { break }
            XCTAssertEqual(
                eng.state.active?.id,
                expected,
                "NEXT preview[0] must equal the piece that spawns after lock"
            )
            XCTAssertEqual(eng.peekNext(1).first, eng.state.queue.first)
        }
    }

    func testFeelConfigLoads() throws {
        let feel = try ConfigLoader.feel()
        XCTAssertGreaterThan(feel.recycleSuckSec, 0)
        XCTAssertLessThanOrEqual(feel.gravityMinSec, feel.gravityBaseSec)
        XCTAssertEqual(BoardGym.allCases.count, 5)
        XCTAssertEqual(BoardGym.clusters.shotName, "recycle")
    }

    func testNoStraightSpanLongerThanThree() {
        for def in JunkCatalog.all {
            for rot in def.rotations {
                let xs = Dictionary(grouping: rot, by: { $0[0] }).mapValues(\.count)
                let ys = Dictionary(grouping: rot, by: { $0[1] }).mapValues(\.count)
                XCTAssertLessThanOrEqual(xs.values.max() ?? 0, 3, "\(def.id) vertical span")
                XCTAssertLessThanOrEqual(ys.values.max() ?? 0, 3, "\(def.id) horizontal span")
                XCTAssertFalse(rot.contains { $0.count != 2 })
            }
        }
    }
}
