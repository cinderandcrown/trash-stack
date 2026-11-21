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

    /// Match clear must only remove the matched cluster; unsupported cells pack; nothing floats.
    func testPacedMatchClearOnlyRemovesMatchedAndPacksGravity() {
        var eng = GameEngine(seed: 77)
        eng.paceCascades = true
        let rows = eng.state.board.config.rows
        eng.seedBoardForTesting(
            cells: [
                // 4 metal along the floor — the match.
                (0, rows - 1, Cell(piece: .can, material: .metal)),
                (1, rows - 1, Cell(piece: .can, material: .metal)),
                (2, rows - 1, Cell(piece: .can, material: .metal)),
                (3, rows - 1, Cell(piece: .can, material: .metal)),
                // Paper resting on the metal — must fall after the clear, not vanish.
                (0, rows - 2, Cell(piece: .crate, material: .paper)),
                // Isolated 3-cell metal L — must survive (follow-ups stay 4+).
                (5, rows - 1, Cell(piece: .bentPipe, material: .metal)),
                (6, rows - 1, Cell(piece: .bentPipe, material: .metal)),
                (6, rows - 2, Cell(piece: .bentPipe, material: .metal)),
                // Lone orange paper — not in the match.
                (7, rows - 1, Cell(piece: .crate, material: .paper)),
            ],
            // Lock a glass piece on col 4 so resolveAfterLock fires the paced clear.
            active: ActivePiece(id: .bottle, x: 4, y: 0)
        )
        eng.hardDrop()

        // After paced clear, gravity has already packed — no unsupported cells.
        assertNoFloatingCells(eng.state.board)

        // Matched metal gone; paper from above packed onto the floor.
        XCTAssertNil(eng.state.board[1, rows - 1])
        XCTAssertNil(eng.state.board[2, rows - 1])
        XCTAssertNil(eng.state.board[3, rows - 1])
        XCTAssertEqual(eng.state.board[0, rows - 1]?.material, .paper)
        XCTAssertNil(eng.state.board[0, rows - 2])

        // Non-matched pieces still present (possibly packed).
        XCTAssertEqual(eng.state.board[5, rows - 1]?.piece, .bentPipe)
        XCTAssertEqual(eng.state.board[6, rows - 1]?.piece, .bentPipe)
        XCTAssertEqual(eng.state.board[6, rows - 2]?.piece, .bentPipe)
        XCTAssertEqual(eng.state.board[7, rows - 1]?.material, .paper)

        // Gravity moves were recorded for the falling paper.
        let fell = eng.lastGravityMoves.contains { $0.to.x == 0 && $0.cell.material == .paper }
        XCTAssertTrue(fell || eng.state.board[0, rows - 1]?.material == .paper)

        // Drain follow-up waves — the 3-cell L must still not recycle.
        var guardTicks = 0
        while eng.cascadeActive, guardTicks < 8 {
            _ = eng.advanceCascade()
            _ = eng.drainEvents()
            assertNoFloatingCells(eng.state.board)
            guardTicks += 1
        }
        XCTAssertEqual(eng.state.board[5, rows - 1]?.piece, .bentPipe)
        XCTAssertEqual(eng.state.board[6, rows - 1]?.piece, .bentPipe)
        XCTAssertEqual(eng.state.board[6, rows - 2]?.piece, .bentPipe)
    }

    /// A piece's id / material / texture must be identical from spawn through lock.
    func testPieceIdentityStableFromSpawnToLock() {
        for id in JunkID.allCases {
            var eng = GameEngine(seed: 99)
            // Paced cascades so a 4-cell square can be inspected before follow-ups spawn.
            eng.paceCascades = true
            eng.seedBoardForTesting(
                cells: [],
                active: ActivePiece(id: id, x: 3, y: 0)
            )
            let expectedMat = JunkCatalog.def(for: id).material
            let expectedTex = JunkCatalog.textureName(for: id)
            var steps = 0
            while let active = eng.state.active, steps < 48 {
                XCTAssertEqual(active.id, id, "id changed mid-fall for \(id)")
                XCTAssertEqual(active.def.material, expectedMat, "material changed mid-fall for \(id)")
                XCTAssertEqual(
                    JunkCatalog.textureName(for: active.id),
                    expectedTex,
                    "texture changed mid-fall for \(id)"
                )
                if eng.isGrounded() {
                    let cells = active.cells
                    eng.lock()
                    // Lock must commit spawn identity. A full-piece recycle (crate/tire/fridge)
                    // may clear those cells in the same wave — surviving cells must still match.
                    for (x, y) in cells {
                        guard let locked = eng.state.board[x, y] else { continue }
                        XCTAssertEqual(locked.piece, id, "locked piece for \(id)")
                        XCTAssertEqual(locked.material, expectedMat, "locked material for \(id)")
                    }
                    for y in 0..<eng.state.board.config.rows {
                        for x in 0..<eng.state.board.config.cols {
                            guard let c = eng.state.board[x, y], c.piece == id else { continue }
                            XCTAssertEqual(c.material, expectedMat, "board material flip for \(id)")
                        }
                    }
                    break
                }
                XCTAssertTrue(eng.softDrop(), "soft drop should advance \(id)")
                steps += 1
            }
            XCTAssertLessThan(steps, 48, "never locked \(id)")
        }
    }

    /// Lock must never rewrite a plastic pipe into metal (old leaking-pipe hazard bug).
    func testLockPreservesPipePlasticMaterial() {
        var eng = GameEngine(seed: 3)
        eng.paceCascades = true
        eng.seedBoardForTesting(cells: [], active: ActivePiece(id: .pipe, x: 2, y: 0))
        var steps = 0
        while !eng.isGrounded(), steps < 48 {
            _ = eng.softDrop()
            steps += 1
        }
        let cells = eng.state.active!.cells
        eng.lock()
        for (x, y) in cells {
            XCTAssertEqual(eng.state.board[x, y]?.piece, .pipe)
            XCTAssertEqual(eng.state.board[x, y]?.material, .plastic)
        }
    }

    /// Every catalog entry's texture must belong to its material's icon family.
    func testMaterialLookMapIsHonest() {
        let allowed: [Material: Set<String>] = [
            .metal: ["can"],
            .plastic: ["pipe", "plastic", "tire"],
            .glass: ["glass", "bottle"],
            .paper: ["plank", "cardboard", "crate", "pizza"],
        ]
        for def in JunkCatalog.all {
            let ok = allowed[def.material] ?? []
            XCTAssertTrue(
                ok.contains(def.textureName),
                "\(def.id) material \(def.material) must not use texture '\(def.textureName)' (allowed \(ok))"
            )
        }
        // Pink bottle bar is plastic — never metal.
        XCTAssertEqual(JunkCatalog.def(for: .pipe).material, .plastic)
        XCTAssertEqual(JunkCatalog.textureName(for: .pipe), "pipe")
        // Metal L / fridge share the steel can icon (not banana / cardboard).
        XCTAssertEqual(JunkCatalog.def(for: .bentPipe).material, .metal)
        XCTAssertEqual(JunkCatalog.textureName(for: .bentPipe), "can")
        XCTAssertEqual(JunkCatalog.def(for: .fridge).material, .metal)
        XCTAssertEqual(JunkCatalog.textureName(for: .fridge), "can")
    }

    /// After a match clear, every remaining tile must rest on the floor or another tile.
    func testSettleAfterClearLeavesNoFloatingTiles() {
        var eng = GameEngine(seed: 11)
        eng.paceCascades = true
        let rows = eng.state.board.config.rows
        eng.seedBoardForTesting(
            cells: [
                (0, rows - 1, Cell(piece: .can, material: .metal)),
                (1, rows - 1, Cell(piece: .can, material: .metal)),
                (2, rows - 1, Cell(piece: .can, material: .metal)),
                (3, rows - 1, Cell(piece: .can, material: .metal)),
                // Swirl-looking tire (plastic) sitting on the metal — must pack after clear.
                (1, rows - 2, Cell(piece: .tire, material: .plastic)),
                (2, rows - 2, Cell(piece: .tire, material: .plastic)),
                (1, rows - 3, Cell(piece: .plank, material: .paper)),
            ],
            active: ActivePiece(id: .bottle, x: 5, y: 0)
        )
        eng.hardDrop()
        assertNoFloatingCells(eng.state.board)
        XCTAssertEqual(eng.state.board[1, rows - 1]?.material, .plastic)
        XCTAssertEqual(eng.state.board[2, rows - 1]?.material, .plastic)
        XCTAssertEqual(eng.state.board[1, rows - 2]?.material, .paper)
        XCTAssertFalse(eng.lastGravityMoves.isEmpty, "clear settle must record gravity moves")
    }

    /// After SLAM crushes the bottom rows, the stack above must pack with no gaps.
    func testSettleAfterSlamLeavesNoFloatingTiles() {
        var eng = GameEngine(seed: 12)
        eng.paceCascades = true
        let rows = eng.state.board.config.rows
        // Mixed column so the post-slam pack does not form a 4+ recycle by itself.
        eng.seedBoardForTesting(
            cells: [
                (0, rows - 1, Cell(piece: .plank, material: .paper)),
                (1, rows - 1, Cell(piece: .plank, material: .paper)),
                (2, rows - 1, Cell(piece: .plank, material: .paper)),
                (3, rows - 1, Cell(piece: .plank, material: .paper)),
                (0, rows - 2, Cell(piece: .plank, material: .paper)),
                (1, rows - 2, Cell(piece: .plank, material: .paper)),
                (2, rows - 2, Cell(piece: .plank, material: .paper)),
                (3, rows - 2, Cell(piece: .plank, material: .paper)),
                // Floating stack above the crush zone — must settle onto the floor.
                (0, rows - 4, Cell(piece: .can, material: .metal)),
                (0, rows - 5, Cell(piece: .tire, material: .plastic)),
                (1, rows - 4, Cell(piece: .bottle, material: .glass)),
                (2, rows - 3, Cell(piece: .crate, material: .paper)),
                (2, rows - 4, Cell(piece: .crate, material: .paper)),
            ],
            active: nil
        )
        eng.fillPressMeter()
        XCTAssertTrue(eng.slamPress())
        assertNoFloatingCells(eng.state.board)
        // Drain follow-ups — every wave must leave a packed board.
        var guardTicks = 0
        while eng.cascadeActive, guardTicks < 8 {
            _ = eng.advanceCascade()
            assertNoFloatingCells(eng.state.board)
            guardTicks += 1
        }
        assertNoFloatingCells(eng.state.board)
        // Something from above the crush zone must now sit on the floor.
        XCTAssertNotNil(eng.state.board[0, rows - 1])
        XCTAssertNotNil(eng.state.board[1, rows - 1])
    }

    /// Render texture, match material, and callout label all share one material field.
    func testEveryPieceKindMaterialTextureAndLabelAgree() {
        for id in JunkID.allCases {
            let def = JunkCatalog.def(for: id)
            let cell = Cell(piece: id, material: def.material)
            let tex = JunkCatalog.textureName(for: cell)
            let label = JunkCatalog.label(for: cell.material)
            XCTAssertEqual(cell.material, def.material, "\(id) cell material")
            XCTAssertEqual(tex, def.textureName, "\(id) display texture must match catalog")
            XCTAssertEqual(label, def.material.rawValue.uppercased(), "\(id) label")
            // No swirl / banana art for any playable piece.
            XCTAssertNotEqual(tex, "banana", "\(id) must not use swirl banana art")
            XCTAssertNotEqual(tex, "bentPipe", "\(id) must not use raw bentPipe swirl key")
        }
        // Hazard conversion keeps texture/label/match on the same material.
        var corroded = Cell(piece: .crate, material: .paper)
        corroded.material = .metal
        corroded.piece = JunkCatalog.representativePiece(for: .metal)
        XCTAssertEqual(corroded.material, .metal)
        XCTAssertEqual(JunkCatalog.textureName(for: corroded), "can")
        XCTAssertEqual(JunkCatalog.label(for: corroded.material), "METAL")
    }

    /// Seeded: paper 2×2 sitting on pink plastic — paper clears, plastic remains and packs.
    func testPaperClearLeavesPlasticBelowAndPacks() {
        var eng = GameEngine(seed: 42)
        eng.paceCascades = true
        let rows = eng.state.board.config.rows
        eng.seedBoardForTesting(
            cells: [
                // Pink plastic on the floor (only 2 — must NOT recycle).
                (1, rows - 1, Cell(piece: .tire, material: .plastic)),
                (2, rows - 1, Cell(piece: .tire, material: .plastic)),
                // Paper 2×2 sitting on that plastic.
                (1, rows - 2, Cell(piece: .crate, material: .paper)),
                (2, rows - 2, Cell(piece: .crate, material: .paper)),
                (1, rows - 3, Cell(piece: .crate, material: .paper)),
                (2, rows - 3, Cell(piece: .crate, material: .paper)),
                // Glass resting on the paper — must fall onto plastic after the clear.
                (1, rows - 4, Cell(piece: .bottle, material: .glass)),
            ],
            active: ActivePiece(id: .can, x: 5, y: 0)
        )
        eng.hardDrop()

        let recycled = eng.drainEvents().compactMap { e -> Material? in
            if case .recycled(_, _, _, _, let mat, _) = e { return mat }
            return nil
        }
        XCTAssertEqual(recycled, [.paper], "only the paper group should clear")
        assertNoFloatingCells(eng.state.board)

        // Plastic stayed on the floor.
        XCTAssertEqual(eng.state.board[1, rows - 1]?.material, .plastic)
        XCTAssertEqual(eng.state.board[2, rows - 1]?.material, .plastic)
        // Paper gone; glass packed onto the plastic.
        XCTAssertNil(eng.state.board[1, rows - 3])
        XCTAssertNil(eng.state.board[2, rows - 3])
        XCTAssertEqual(eng.state.board[1, rows - 2]?.material, .glass)
        XCTAssertTrue(
            eng.lastGravityMoves.contains { $0.cell.material == .glass && $0.to.x == 1 },
            "glass should record a gravity fall onto the pink plastic"
        )

        var guardTicks = 0
        while eng.cascadeActive, guardTicks < 8 {
            _ = eng.advanceCascade()
            _ = eng.drainEvents()
            assertNoFloatingCells(eng.state.board)
            guardTicks += 1
        }
        // Still only 2 plastic — never a follow-up clear of the pink.
        XCTAssertEqual(eng.state.board[1, rows - 1]?.material, .plastic)
        XCTAssertEqual(eng.state.board[2, rows - 1]?.material, .plastic)
    }

    private func assertNoFloatingCells(_ board: Board, file: StaticString = #filePath, line: UInt = #line) {
        let rows = board.config.rows
        let cols = board.config.cols
        for x in 0..<cols {
            var seenEmpty = false
            for y in (0..<rows).reversed() {
                if board[x, y] == nil {
                    seenEmpty = true
                } else {
                    XCTAssertFalse(seenEmpty, "unsupported cell at (\(x),\(y))", file: file, line: line)
                }
            }
        }
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
        XCTAssertEqual(FeelConfig.fallback.arrIntervalSec, 0.11, accuracy: 0.001)
        XCTAssertEqual(FeelConfig.fallback.softRepeatSec, 0.11, accuracy: 0.001)
        XCTAssertEqual(FeelConfig.fallback.cellTweenSec, 0.11, accuracy: 0.001)
        XCTAssertEqual(FeelConfig.fallback.rotateTweenSec, 0.10, accuracy: 0.001)
        XCTAssertEqual(FeelConfig.fallback.settleBounceSec, 0.14, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(feel.cellTweenSec, 0.10)
        XCTAssertLessThanOrEqual(feel.cellTweenSec, 0.12)
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
        XCTAssertGreaterThanOrEqual(peak, 2, "follow-up 4+ packs should create real chains")
        let eng = GameEngine(seed: 1)
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
