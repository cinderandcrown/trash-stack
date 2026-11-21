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
        XCTAssertEqual(PlayMode.allCases.count, 4)
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
        XCTAssertEqual(FeelConfig.fallback.recycleSuckSec, 0.34, accuracy: 0.001)
        XCTAssertEqual(FeelConfig.fallback.shakeRecycle, 10, accuracy: 0.001)
        XCTAssertEqual(FeelConfig.fallback.gravityBaseSec, 0.72, accuracy: 0.001)
        XCTAssertEqual(FeelConfig.fallback.cascadeStepSec, 0.30, accuracy: 0.001)
        XCTAssertEqual(FeelConfig.fallback.dasDelaySec, 0.16, accuracy: 0.001)
        XCTAssertEqual(FeelConfig.fallback.arrIntervalSec, 0.045, accuracy: 0.001)
    }

    func testComboScoreEscalatesWithCap() {
        let single = Scoring.recycleScore(cells: 4, groups: 1, level: 1, chain: 1)
        let double = Scoring.recycleScore(cells: 4, groups: 1, level: 1, chain: 2)
        let mega = Scoring.recycleScore(cells: 4, groups: 1, level: 1, chain: 4)
        let capped = Scoring.recycleScore(cells: 4, groups: 1, level: 1, chain: 9)
        XCTAssertEqual(double, single * 2)
        XCTAssertEqual(mega, single * 3) // hard cap
        XCTAssertEqual(capped, mega)
        XCTAssertEqual(Scoring.linesPerLevel, 14)
    }

    func testCascadesProduceChainsInNormalPlay() {
        // Empty-board play used to peak at combo 1; follow-up triples should raise that.
        var peak = 0
        var recycleWaves = 0
        for seed in [UInt64(7), 42, 99] {
            var eng = GameEngine(seed: seed)
            for _ in 0..<100 {
                if eng.state.over { break }
                eng.hardDrop()
                for e in eng.drainEvents() {
                    if case .recycled = e {
                        recycleWaves += 1
                        peak = max(peak, eng.state.combo)
                    }
                }
            }
            if peak >= 2 { break }
        }
        XCTAssertGreaterThan(recycleWaves, 0)
        XCTAssertGreaterThanOrEqual(peak, 2, "follow-up triples should create real chains")
        var eng = GameEngine(seed: 1)
        XCTAssertEqual(eng.state.pressMeterMax, 10)
    }

    /// Plays a seeded run and dumps board frames for visual verify (scripts/render_play_verify.py).
    func testPlayLoopDumpForVerify() throws {
        var eng = GameEngine(seed: 2026_11_19)
        eng.applyShotScenario("demo")
        var log: [String] = []
        var frames: [[[String]]] = []
        func snap() -> [[String]] {
            let hid = eng.state.board.config.hiddenRows
            let vis = eng.state.board.config.visibleRows
            var rows: [[String]] = []
            for y in hid..<(hid + vis) {
                var row: [String] = []
                for x in 0..<eng.state.board.config.cols {
                    if let c = eng.state.board[x, y] {
                        // Distinct letters for the verify renderer (plastic vs paper).
                        switch c.material {
                        case .metal: row.append("m")
                        case .plastic: row.append("p")
                        case .glass: row.append("g")
                        case .paper: row.append("P")
                        }
                    } else {
                        row.append(".")
                    }
                }
                rows.append(row)
            }
            return rows
        }
        frames.append(snap())
        for step in 0..<28 {
            if eng.state.over { break }
            eng.hardDrop()
            let ev = eng.drainEvents()
            for e in ev {
                switch e {
                case .locked(let hard):
                    log.append("step\(step) lock hard=\(hard) score=\(eng.state.score)")
                case .recycled(let groups, let cells, let score, _, let mat, _):
                    log.append("step\(step) recycle \(mat.rawValue) groups=\(groups) cells=\(cells) +\(score) combo=\(eng.state.combo) total=\(eng.state.score)")
                case .leveledUp(let lvl):
                    log.append("step\(step) level \(lvl) · \(LevelTwist.active(at: lvl).playerBlurb)")
                case .gameOver:
                    log.append("step\(step) gameOver score=\(eng.state.score)")
                default: break
                }
            }
            if step == 4 || step == 10 || step == 18 || eng.state.over {
                frames.append(snap())
            }
        }
        XCTAssertFalse(log.isEmpty)
        let payload: [String: Any] = [
            "seed": 2026_11_19,
            "finalScore": eng.state.score,
            "finalLevel": eng.state.level,
            "finalCombo": eng.state.combo,
            "over": eng.state.over,
            "log": log,
            "frames": frames,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        let out = URL(fileURLWithPath: "/tmp/trash-stack-play-verify.json")
        try data.write(to: out)
        XCTAssertGreaterThan(eng.state.score, 0, "played loop should score")
    }

    /// Fresh New Game (no shot seed) must gravity-lock, recycle, and eventually top out.
    func testFreshNewGameClearsAndCanTopOut() {
        var eng = GameEngine(seed: 4242)
        eng.paceCascades = true
        XCTAssertFalse(eng.state.over)
        XCTAssertNotNil(eng.state.active)
        XCTAssertEqual(eng.state.score, 0)

        var recycles = 0
        var lastScore = 0
        for step in 0..<400 {
            if eng.state.over { break }
            // Alternate nudges so clusters can form, then hard-drop to stack.
            _ = eng.tryMove(dx: step % 2 == 0 ? -1 : 1, dy: 0)
            if step % 3 == 0 { _ = eng.tryRotate() }
            eng.hardDrop()
            for e in eng.drainEvents() {
                if case .recycled = e { recycles += 1 }
            }
            XCTAssertGreaterThanOrEqual(eng.state.score, lastScore, "score must never go backwards")
            lastScore = eng.state.score
            // Settle paced cascades the way CompactorScene does.
            var guardTicks = 0
            while eng.cascadeActive, guardTicks < 24 {
                _ = eng.advanceCascade()
                for e in eng.drainEvents() {
                    if case .recycled = e { recycles += 1 }
                }
                guardTicks += 1
            }
        }
        XCTAssertGreaterThanOrEqual(recycles, 2, "fresh run should produce at least two recycles")
        XCTAssertGreaterThan(eng.state.score, 0)
        // Keep dropping until overflow if not already topped out.
        var safety = 0
        while !eng.state.over, safety < 500 {
            eng.hardDrop()
            _ = eng.drainEvents()
            var guardTicks = 0
            while eng.cascadeActive, guardTicks < 24 {
                _ = eng.advanceCascade()
                _ = eng.drainEvents()
                guardTicks += 1
            }
            safety += 1
        }
        XCTAssertTrue(eng.state.over, "fresh New Game must be able to reach natural game over")
        XCTAssertGreaterThan(eng.state.score, 0, "final score must be > 0 at game over")
    }

    func testLevelNeverGoesBackwardsAfterShotSeed() {
        var eng = GameEngine(seed: 99)
        eng.applyShotScenario("game")
        let seeded = eng.state.level
        XCTAssertGreaterThanOrEqual(seeded, 3)
        XCTAssertGreaterThanOrEqual(eng.state.lines, (seeded - 1) * 8)
        // Drive a lock+recycle path; level must not drop below the staged seed.
        for _ in 0..<24 {
            if eng.state.over { break }
            eng.hardDrop()
            XCTAssertGreaterThanOrEqual(eng.state.level, seeded, "level must never rewind below seeded \(seeded)")
        }
    }

    func testLevelTwistsEscalate() {
        XCTAssertEqual(LevelTwist.active(at: 1), .nightWarmup)
        XCTAssertEqual(LevelTwist.active(at: 3), .stickyCans)
        XCTAssertEqual(LevelTwist.active(at: 5), .denseJunk)
        XCTAssertEqual(LevelTwist.active(at: 7), .nightRush)
        XCTAssertEqual(LevelTwist.active(at: 99), .nightRush)
        XCTAssertTrue(LevelTwist.denseJunk.playerBlurb.lowercased().contains("junk"))
        XCTAssertTrue(LevelTwist.alleyGusts.toastTitle.contains("Gust") || LevelTwist.alleyGusts.playerBlurb.lowercased().contains("gust"))
        var eng = GameEngine(seed: 7)
        // Fresh run is level 1 — full lock window.
        XCTAssertEqual(eng.lockDelaySeconds(base: 0.42), 0.42, accuracy: 0.001)
        eng.applyShotScenario("revive") // level 6 — still below Night Rush
        XCTAssertEqual(eng.lockDelaySeconds(base: 0.42), 0.42, accuracy: 0.001)
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

    /// Rich empty-board play session for feel QA (seeds 42 & 7, 60 steps).
    func testPlayFeelSessionSeeds42And7() throws {
        struct Near { let material: Material; let size: Int }
        func nearOfSize(_ board: Board, size: Int) -> [Near] {
            var seen = Set<String>()
            var out: [Near] = []
            for y in 0..<board.config.rows {
                for x in 0..<board.config.cols {
                    let key = "\(x),\(y)"
                    guard !seen.contains(key), let cell = board[x, y], !cell.sticky else { continue }
                    var stack = [(x, y)]
                    var cluster: [(Int, Int)] = []
                    seen.insert(key)
                    while let (cx, cy) = stack.popLast() {
                        cluster.append((cx, cy))
                        for (nx, ny) in [(cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)] {
                            let nk = "\(nx),\(ny)"
                            guard !seen.contains(nk), board.inBounds(x: nx, y: ny),
                                  let n = board[nx, ny], !n.sticky,
                                  n.material == cell.material else { continue }
                            seen.insert(nk)
                            stack.append((nx, ny))
                        }
                    }
                    if cluster.count == size {
                        out.append(Near(material: cell.material, size: size))
                    }
                }
            }
            return out
        }

        var allLines: [String] = []
        func log(_ s: String) { allLines.append(s); print(s) }

        for seed in [UInt64(42), UInt64(7)] {
            var eng = GameEngine(seed: seed) // empty — no shot scenario
            log("=== SEED \(seed) empty start active=\(eng.state.active?.id.rawValue ?? "nil") ===")
            var recycleCount = 0
            var comboPeak = 0
            var comboGe2 = 0
            var pressFills = 0
            var pressSlams = 0
            var near3Peak = 0
            var near3Sum = 0
            var firstRecycleStep: Int?
            var lastPress = eng.state.pressMeter
            var locks = 0

            for step in 0..<60 {
                if eng.state.over {
                    log("step\(step) GAME_OVER score=\(eng.state.score) level=\(eng.state.level) locks=\(locks)")
                    break
                }
                if step % 3 == 0 { _ = eng.tryRotate() }
                _ = eng.tryMove(dx: (step % 2 == 0) ? -1 : 1, dy: 0)
                for _ in 0..<((step % 4) + 1) { _ = eng.softDrop() }
                eng.hardDrop()
                locks += 1

                if eng.state.pressMeter >= eng.state.pressMeterMax, step % 2 == 0 {
                    if eng.slamPress() {
                        pressSlams += 1
                        log("step\(step) PRESS_SLAM score=\(eng.state.score) combo=\(eng.state.combo)")
                    }
                }

                for e in eng.drainEvents() {
                    switch e {
                    case .recycled(let groups, let cells, let score, let scrap, let mat, _):
                        recycleCount += 1
                        if firstRecycleStep == nil { firstRecycleStep = step }
                        let combo = eng.state.combo
                        comboPeak = max(comboPeak, combo)
                        if combo >= 2 { comboGe2 += 1 }
                        log("step\(step) RECYCLE \(mat.rawValue) g=\(groups) cells=\(cells) +\(score) scrap=\(scrap) combo=\(combo) total=\(eng.state.score) press=\(eng.state.pressMeter)/\(eng.state.pressMeterMax)")
                    case .pressed(let cells, let score, let scrap):
                        log("step\(step) PRESSED cells=\(cells) +\(score) scrap=\(scrap)")
                    case .leveledUp(let lvl):
                        log("step\(step) LEVEL \(lvl)")
                    default: break
                    }
                }

                if eng.state.pressMeter == eng.state.pressMeterMax, lastPress < eng.state.pressMeterMax {
                    pressFills += 1
                    log("step\(step) PRESS_FULL \(eng.state.pressMeter)/\(eng.state.pressMeterMax)")
                }
                lastPress = eng.state.pressMeter

                let n3 = nearOfSize(eng.state.board, size: 3)
                near3Sum += n3.count
                near3Peak = max(near3Peak, n3.count)
                if !n3.isEmpty, step % 5 == 0 || n3.count >= 2 {
                    let by = Dictionary(grouping: n3, by: \.material.rawValue).mapValues(\.count)
                    log("step\(step) NEAR3 \(n3.count) \(by) press=\(eng.state.pressMeter)")
                }
            }

            log("END seed=\(seed) score=\(eng.state.score) lvl=\(eng.state.level) lines=\(eng.state.lines) over=\(eng.state.over) press=\(eng.state.pressMeter)/\(eng.state.pressMeterMax)")
            log("STATS seed=\(seed) recycles=\(recycleCount) comboPeak=\(comboPeak) combo>=2=\(comboGe2) pressFills=\(pressFills) pressSlams=\(pressSlams) near3Peak=\(near3Peak) near3Sum=\(near3Sum) firstRecycle=\(firstRecycleStep.map(String.init) ?? "none") locks=\(locks) recycledBy=\(eng.state.recycledByMaterial)")
        }

        let out = URL(fileURLWithPath: "/tmp/trash-stack-feel-play.log")
        try allLines.joined(separator: "\n").write(to: out, atomically: true, encoding: .utf8)
        XCTAssertTrue(FileManager.default.fileExists(atPath: out.path))
    }
}
