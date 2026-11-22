// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

/// Earned boosters — never sold. Counts are how many the player has ready.
public struct BoosterInventory: Sendable, Equatable {
    public var magnet: Int
    public var crusher: Int
    public var slam: Int
    public var shuffle: Int

    public init(magnet: Int = 1, crusher: Int = 1, slam: Int = 0, shuffle: Int = 1) {
        self.magnet = magnet
        self.crusher = crusher
        self.slam = slam
        self.shuffle = shuffle
    }
}

public enum PlacementFit: Sendable, Equatable {
    case fits
    case blocked
}

public enum LevelOutcome: Sendable, Equatable {
    case playing
    case won(stars: Int)
    case lost
}

extension GameEngine {
    /// Opt into classic falling-piece mode (unit tests / legacy shots).
    public mutating func enableClassicFallingMode() {
        state.isTurnBased = false
        state.isDailySort = false
    }

    /// Start a hand-tuned Shift level (turn-based, prefilled board, move limit).
    public mutating func startLevel(_ def: LevelDef, seed: UInt64 = 0xC1A55) {
        state = GameState(config: state.board.config)
        state.isTurnBased = true
        state.isDailySort = false
        state.levelId = def.id
        state.level = def.id
        state.moveLimit = def.moveLimit
        state.movesLeft = def.moveLimit
        state.teachHint = def.teachHint
        state.orders = [def.goal]
        state.boosters = BoosterInventory(magnet: def.id >= 5 ? 1 : 0, crusher: 1, slam: 0, shuffle: 1)
        bag = RNGBag(seed: seed &+ UInt64(def.id) &* 17)
        events = []
        placeCount = 0
        cascadeActive = false
        lastGravityMoves = []
        seedBoardForTesting(cells: def.board, active: nil)
        state.tray = def.tray.map { Optional($0) }
        while state.tray.count < 3 { state.tray.append(nil) }
        state.selectedTrayIndex = nil
        state.active = nil
        checkTrayFitsOrLose()
    }

    /// Start today's Daily Sort puzzle.
    public mutating func startDailySort(_ puzzle: DailySortPuzzle) {
        state = GameState(config: state.board.config)
        state.isTurnBased = true
        state.isDailySort = true
        state.levelId = 0
        state.lives = puzzle.lives
        state.dailyStepIndex = 0
        state.moveLimit = 99
        state.movesLeft = 99
        state.teachHint = "Find the forced move — or use Hint"
        state.orders = [puzzle.goal]
        state.boosters = BoosterInventory(magnet: 0, crusher: 0, slam: 0, shuffle: 0)
        events = []
        placeCount = 0
        seedBoardForTesting(cells: puzzle.board, active: nil)
        let deal = puzzle.trayDeals.first ?? [.can, .plank, .bottle]
        state.tray = deal.map { Optional($0) }
        while state.tray.count < 3 { state.tray.append(nil) }
        state.selectedTrayIndex = nil
        state.active = nil
    }

    /// Select a tray slot (0…2). Builds a preview piece at a default seat.
    @discardableResult
    public mutating func selectTray(_ index: Int) -> Bool {
        guard state.isTurnBased, !state.over, !state.levelWon, !cascadeActive else { return false }
        guard state.tray.indices.contains(index), let id = state.tray[index] else { return false }
        state.selectedTrayIndex = index
        let hid = state.board.config.hiddenRows
        state.active = ActivePiece(id: id, x: 3, y: hid + 2)
        events.append(.spawned(id))
        return true
    }

    /// Move / rotate the preview piece. Does not place. Returns whether the pose fits.
    @discardableResult
    public mutating func setPreview(x: Int, y: Int, rot: Int? = nil) -> PlacementFit {
        guard state.isTurnBased, var p = state.active else { return .blocked }
        p.x = x
        p.y = y
        if let rot { p.rot = rot }
        state.active = p
        return p.fits(state.board) ? .fits : .blocked
    }

    @discardableResult
    public mutating func rotatePreview(clockwise: Bool = true) -> PlacementFit {
        guard state.isTurnBased, var p = state.active else { return .blocked }
        let n = p.def.rotations.count
        p.rot = clockwise ? (p.rot + 1) % n : (p.rot + n - 1) % n
        state.active = p
        return p.fits(state.board) ? .fits : .blocked
    }

    /// Place the selected tray piece at the current preview pose. No gravity on place.
    @discardableResult
    public mutating func placeSelected() -> Bool {
        guard state.isTurnBased, !state.over, !state.levelWon, !cascadeActive else { return false }
        guard let idx = state.selectedTrayIndex, let id = state.tray[idx], let p = state.active else {
            return false
        }
        guard p.id == id, p.fits(state.board) else { return false }

        for (x, y) in p.cells {
            guard !state.board.occupied(x: x, y: y) else { return false }
        }
        for (x, y) in p.cells {
            state.board[x, y] = Cell(piece: p.id, material: p.material)
        }
        let anchor = BoardCoord(p.x, p.y)
        state.tray[idx] = nil
        state.selectedTrayIndex = nil
        state.active = nil
        state.movesLeft = max(0, state.movesLeft - 1)
        placeCount += 1
        state.pressMeter = min(state.pressMeterMax, state.pressMeter + 1)
        if state.pressMeter >= state.pressMeterMax {
            state.boosters.slam += 1
            state.pressMeter = 0
        }
        events.append(.placed(id, at: anchor))
        events.append(.locked(hard: false))

        // Recycle + model-driven settle (gravity only after clears).
        // When paced, defer win/lose until the cascade finishes so chains stay on camera.
        if paceCascades {
            beginPacedCascade(firstWaveMinSize: RecycleMatcher.defaultMinSize, followUpMinSize: 4, needsSpawn: false)
            dealTrayIfEmpty()
            if !cascadeActive {
                evaluateLevelOutcome()
                if !state.levelWon, !state.over {
                    checkTrayFitsOrLose()
                }
            }
        } else {
            _ = runRecycleCascades(firstWaveMinSize: RecycleMatcher.defaultMinSize, followUpMinSize: 4)
            dealTrayIfEmpty()
            evaluateLevelOutcome()
            if !state.levelWon, !state.over {
                checkTrayFitsOrLose()
            }
        }
        return true
    }

    /// True if the piece can sit at any in-bounds pose (any rotation).
    public func canPlaceAnywhere(_ id: JunkID) -> Bool {
        let def = JunkCatalog.def(for: id)
        let cols = state.board.config.cols
        let rows = state.board.config.rows
        let hid = state.board.config.hiddenRows
        for rot in 0..<def.rotations.count {
            for y in hid..<rows {
                for x in 0..<cols {
                    var piece = ActivePiece(id: id, x: x, y: y)
                    piece.rot = rot
                    if piece.fits(state.board) { return true }
                }
            }
        }
        return false
    }

    public func anyTrayPieceFits() -> Bool {
        for slot in state.tray {
            guard let id = slot else { continue }
            if canPlaceAnywhere(id) { return true }
        }
        return false
    }

    public mutating func dealTrayIfEmpty() {
        guard state.tray.allSatisfy({ $0 == nil }) else { return }
        var next: [JunkID?] = []
        for _ in 0..<3 {
            next.append(bag.next())
        }
        state.tray = next
        events.append(.spawned(next.compactMap { $0 }.first ?? .can))
    }

    /// Shuffle rescue — costs one earned shuffle; redeals tray from the bag.
    @discardableResult
    public mutating func useShuffle() -> Bool {
        guard state.isTurnBased, !state.over, !state.levelWon else { return false }
        guard state.boosters.shuffle > 0 else { return false }
        state.boosters.shuffle -= 1
        state.tray = [bag.next(), bag.next(), bag.next()]
        state.selectedTrayIndex = nil
        state.active = nil
        events.append(.shuffled)
        checkTrayFitsOrLose()
        return true
    }

    /// Magnet — clear every non-sticky cell of one material.
    @discardableResult
    public mutating func useMagnet(material: Material) -> Bool {
        guard state.isTurnBased, !state.over, !state.levelWon, !cascadeActive else { return false }
        guard state.boosters.magnet > 0 else { return false }
        var coords: [BoardCoord] = []
        for y in 0..<state.board.config.rows {
            for x in 0..<state.board.config.cols {
                guard let c = state.board[x, y], c.material == material, !c.sticky else { continue }
                state.board[x, y] = nil
                coords.append(BoardCoord(x, y))
            }
        }
        guard !coords.isEmpty else { return false }
        state.boosters.magnet -= 1
        state.recycledByMaterial[material, default: 0] += coords.count
        bumpOrderMaterial(material, amount: coords.count)
        bumpOrder(kind: .recycleAny, amount: coords.count)
        let score = Scoring.recycleScore(cells: coords.count, groups: 1, level: max(1, state.level), chain: 1)
        state.score += score
        events.append(.magnetUsed)
        events.append(.recycled(
            groups: 1, cells: coords.count, score: score, scrap: coords.count / 2,
            material: material, coords: coords
        ))
        lastGravityMoves = applyGravity()
        lastGravityMoves = Self.mergeGravityMoves(lastGravityMoves, applyGravity())
        if paceCascades {
            beginPacedCascade(firstWaveMinSize: RecycleMatcher.defaultMinSize, followUpMinSize: 4, needsSpawn: false)
        } else {
            _ = runRecycleCascades(firstWaveMinSize: RecycleMatcher.defaultMinSize, followUpMinSize: 4)
        }
        evaluateLevelOutcome()
        return true
    }

    /// Crusher — remove one tile.
    @discardableResult
    public mutating func useCrusher(x: Int, y: Int) -> Bool {
        guard state.isTurnBased, !state.over, !state.levelWon, !cascadeActive else { return false }
        guard state.boosters.crusher > 0, state.board[x, y] != nil else { return false }
        state.boosters.crusher -= 1
        state.board[x, y] = nil
        events.append(.crushed(BoardCoord(x, y)))
        lastGravityMoves = applyGravity()
        if paceCascades {
            beginPacedCascade(firstWaveMinSize: RecycleMatcher.defaultMinSize, followUpMinSize: 4, needsSpawn: false)
        } else {
            _ = runRecycleCascades(firstWaveMinSize: RecycleMatcher.defaultMinSize, followUpMinSize: 4)
        }
        evaluateLevelOutcome()
        return true
    }

    /// SLAM booster — crush bottom 2 rows (same as press).
    @discardableResult
    public mutating func useSlamBooster() -> Bool {
        guard state.isTurnBased, !state.over, !state.levelWon else { return false }
        guard state.boosters.slam > 0 || state.pressMeter >= state.pressMeterMax else { return false }
        if state.boosters.slam > 0 {
            state.boosters.slam -= 1
        }
        // Ensure meter is full so slamPress accepts.
        state.pressMeter = state.pressMeterMax
        let ok = slamPress()
        evaluateLevelOutcome()
        return ok
    }

    public func starRating(movesLeft: Int, def: LevelDef) -> Int {
        if movesLeft >= def.starThreeMoves { return 3 }
        if movesLeft >= def.starTwoMoves { return 2 }
        return 1
    }

    public mutating func evaluateLevelOutcome() {
        guard state.isTurnBased, !state.levelWon else { return }
        // Goals met?
        let goalsDone = state.orders.allSatisfy(\.done)
        if goalsDone {
            let def = LevelCatalog.level(id: max(1, state.levelId))
            let stars = state.isDailySort ? 3 : starRating(movesLeft: state.movesLeft, def: def)
            state.starsEarned = stars
            state.levelWon = true
            state.active = nil
            events.append(.levelWon(stars: stars))
            return
        }
        if state.movesLeft <= 0 {
            loseLevel(spendLife: state.isDailySort)
        }
    }

    public mutating func checkTrayFitsOrLose() {
        guard state.isTurnBased, !state.levelWon, !state.over else { return }
        if state.tray.allSatisfy({ $0 == nil }) {
            dealTrayIfEmpty()
        }
        if anyTrayPieceFits() { return }
        // No piece fits — offer shuffle if available; else lose.
        if state.boosters.shuffle > 0 {
            // Soft lock: player must tap shuffle. Do not auto-lose.
            return
        }
        loseLevel(spendLife: state.isDailySort)
    }

    private mutating func loseLevel(spendLife: Bool) {
        if spendLife {
            state.lives -= 1
            if state.lives > 0 {
                // Retry same board — caller reloads. Mark over for UI.
                state.over = true
                events.append(.gameOver)
                return
            }
        }
        state.over = true
        events.append(.gameOver)
    }

    /// Hint for Daily Sort — returns next forced step without placing.
    public func dailyHint(puzzle: DailySortPuzzle) -> DailySortStep? {
        DailySortCatalog.hint(for: puzzle, stepIndex: state.dailyStepIndex)
    }

    public var levelOutcome: LevelOutcome {
        if state.levelWon { return .won(stars: state.starsEarned) }
        if state.over { return .lost }
        return .playing
    }
}
