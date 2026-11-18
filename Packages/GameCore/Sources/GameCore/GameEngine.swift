// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

public struct BoardCoord: Sendable, Equatable, Hashable {
    public var x: Int
    public var y: Int
    public init(_ x: Int, _ y: Int) { self.x = x; self.y = y }
}

public enum GameEvent: Sendable, Equatable {
    case spawned(JunkID)
    /// `hard` is true after a slam drop — bigger impact juice.
    case locked(hard: Bool)
    /// `coords` are board cells sucked into the chute (for VFX).
    case recycled(groups: Int, cells: Int, score: Int, scrap: Int, material: Material, coords: [BoardCoord])
    case pressed(cells: Int, score: Int, scrap: Int)
    case orderCompleted(OrderTicket)
    case snatchUsed
    case magnetUsed // legacy alias unused
    case gameOver
    case leveledUp(Int)
}

public struct OrderTicket: Sendable, Equatable, Identifiable {
    public var id: String
    public var label: String
    public var kind: Kind
    public var target: Int
    public var progress: Int
    public var done: Bool { progress >= target }

    public enum Kind: String, Sendable, Equatable {
        case recycleMaterial
        case recycleChain
        case pressSlam
        case recycleAny
    }

    public var material: Material?

    public init(id: String, label: String, kind: Kind, target: Int, progress: Int = 0, material: Material? = nil) {
        self.id = id
        self.label = label
        self.kind = kind
        self.target = target
        self.progress = progress
        self.material = material
    }
}

public struct GameState: Sendable, Equatable {
    public var board: Board
    public var active: ActivePiece?
    public var hold: JunkID?
    public var holdUsed: Bool
    public var queue: [JunkID]
    public var score: Int
    public var lines: Int // recycled clusters (legacy field name kept for profile XP hooks)
    public var level: Int
    public var combo: Int
    public var backToBack: Bool
    public var magnetCharge: Int // unused; snatch replaces
    public var pressMeter: Int
    public var pressMeterMax: Int
    public var snatchAvailable: Bool
    public var orders: [OrderTicket]
    public var over: Bool
    public var runScrap: Int
    public var recycledByMaterial: [Material: Int]

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
        pressMeter = 0
        pressMeterMax = 8
        snatchAvailable = true
        orders = []
        over = false
        runScrap = 0
        recycledByMaterial = [:]
    }
}

/// Pure Recycling Night Shift rules — no SpriteKit / UIKit.
public struct GameEngine: Sendable {
    public private(set) var state: GameState
    private var bag: RNGBag
    public var events: [GameEvent] = []
    private var placeCount = 0

    public init(seed: UInt64 = 0xC1A55, config: BoardConfig = .dumpster) {
        state = GameState(config: config)
        bag = RNGBag(seed: seed)
        fillQueue()
        seedOrders(level: 1)
        spawn()
    }

    public mutating func reset(seed: UInt64) {
        state = GameState(config: state.board.config)
        bag = RNGBag(seed: seed)
        events = []
        placeCount = 0
        fillQueue()
        seedOrders(level: 1)
        spawn()
    }

    public mutating func revive() {
        state.over = false
        // Clear top lip so the run can continue.
        let hid = state.board.config.hiddenRows
        for y in hid..<(hid + 3) {
            for x in 0..<state.board.config.cols {
                state.board[x, y] = nil
            }
        }
        if state.active == nil {
            _ = spawn()
        }
    }

    private mutating func fillQueue() {
        while state.queue.count < 5 {
            state.queue.append(bag.next())
        }
    }

    private mutating func seedOrders(level: Int) {
        let mats = Material.allCases
        let m1 = mats[Int(level) % mats.count]
        let m2 = mats[(Int(level) + 2) % mats.count]
        state.orders = [
            OrderTicket(id: "ord-mat", label: "Recycle 12 \(m1.rawValue)", kind: .recycleMaterial, target: 12, material: m1),
            OrderTicket(id: "ord-chain", label: "Make a 3× chain", kind: .recycleChain, target: 3),
            OrderTicket(id: "ord-press", label: "Slam the press", kind: .pressSlam, target: 1),
        ]
        if level >= 2 {
            state.orders[0] = OrderTicket(id: "ord-mat", label: "Recycle 20 \(m2.rawValue)", kind: .recycleMaterial, target: 20, material: m2)
        }
    }

    /// Next junk IDs that will spawn (front of the queue). Preview UI must use this.
    public func peekNext(_ count: Int = 2) -> [JunkID] {
        Array(state.queue.prefix(count))
    }

    @discardableResult
    public mutating func spawn() -> Bool {
        fillQueue()
        precondition(!state.queue.isEmpty, "spawn queue empty")
        let id = state.queue.removeFirst()
        fillQueue()
        let piece = ActivePiece(id: id, x: max(0, state.board.config.cols / 2 - 1), y: 0)
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
        if p.def.isSquare { return false }
        let old = p.rot
        p.rot = (p.rot + 1) % p.def.rotations.count
        if p.fits(state.board) {
            state.active = p
            return true
        }
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
        lock(hard: true)
    }

    @discardableResult
    public mutating func softDrop() -> Bool {
        tryMove(dx: 0, dy: 1)
    }

    public mutating func lock(hard: Bool = false) {
        guard let p = state.active else { return }
        let def = p.def
        for (x, y) in p.cells {
            var cell = Cell(piece: p.id, material: def.material)
            // Sticky / battery hazards appear after level 3 on occasional placements.
            if state.level >= 3, placeCount % 11 == 7, p.id == .can {
                cell.sticky = true
            }
            if state.level >= 4, placeCount % 17 == 5, p.id == .pipe {
                cell.hazard = .leakingBattery
                cell.material = .metal
            }
            state.board[x, y] = cell
        }
        state.active = nil
        placeCount += 1
        events.append(.locked(hard: hard))
        // Press meter fills on place.
        state.pressMeter = min(state.pressMeterMax, state.pressMeter + max(1, p.cells.count / 2))
        applyHazards()
        resolveAfterLock()
    }

    private mutating func applyHazards() {
        var conversions: [(Int, Int)] = []
        for y in 0..<state.board.config.rows {
            for x in 0..<state.board.config.cols {
                guard let c = state.board[x, y], c.hazard == .leakingBattery else { continue }
                for (nx, ny) in [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)] {
                    guard let neighbor = state.board[nx, ny], neighbor.material != .metal else { continue }
                    conversions.append((nx, ny))
                }
            }
        }
        for (x, y) in conversions {
            guard var n = state.board[x, y] else { continue }
            n.material = .metal
            state.board[x, y] = n
        }
    }

    private mutating func resolveAfterLock() {
        var chain = 0
        var any = false
        while true {
            let groups = RecycleMatcher.findGroups(on: state.board)
            guard !groups.isEmpty else { break }
            any = true
            chain += 1
            var cells = 0
            var primary = groups[0].material
            var coords: [BoardCoord] = []
            for g in groups {
                cells += g.cells.count
                primary = g.material
                coords.append(contentsOf: g.cells.map { BoardCoord($0.0, $0.1) })
                for (x, y) in g.cells { state.board[x, y] = nil }
                state.recycledByMaterial[g.material, default: 0] += g.cells.count
                bumpOrderMaterial(g.material, amount: g.cells.count)
            }
            let score = Scoring.recycleScore(cells: cells, groups: groups.count, level: state.level, chain: chain)
            let scrap = Scoring.scrapForRecycle(groups: groups.count, cells: cells)
            state.score += score
            state.runScrap += scrap
            state.combo = chain
            state.lines += groups.count
            events.append(.recycled(groups: groups.count, cells: cells, score: score, scrap: scrap, material: primary, coords: coords))
            if chain >= 3 {
                bumpOrder(kind: .recycleChain, amount: chain)
            }
            applyGravity()
        }
        if any {
            bumpOrder(kind: .recycleAny, amount: 1)
            checkOrders()
            advanceLevelFromLines()
        } else {
            state.combo = 0
        }

        if !spawn() {
            // game over
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

    /// Player-timed hydraulic press — crushes bottom 2 rows into scrap.
    @discardableResult
    public mutating func slamPress() -> Bool {
        guard !state.over, state.pressMeter >= state.pressMeterMax else { return false }
        let rows = state.board.bottomRowIndices(count: 2)
        var coords: [(Int, Int)] = []
        for y in rows {
            for x in 0..<state.board.config.cols {
                if state.board[x, y] != nil {
                    coords.append((x, y))
                }
            }
        }
        guard !coords.isEmpty else {
            state.pressMeter = 0
            return false
        }
        // Press unsticks sticky cells in those rows by crushing them.
        state.board.clearCells(coords)
        let score = Scoring.pressScore(cells: coords.count, level: state.level)
        let scrap = Scoring.scrapForPress(cells: coords.count)
        state.score += score
        state.runScrap += scrap
        state.pressMeter = 0
        events.append(.pressed(cells: coords.count, score: score, scrap: scrap))
        bumpOrder(kind: .pressSlam, amount: 1)
        applyGravity()
        // Settling can create recycle chains.
        var chain = 0
        while true {
            let groups = RecycleMatcher.findGroups(on: state.board)
            guard !groups.isEmpty else { break }
            chain += 1
            var cells = 0
            var primary = groups[0].material
            var cleared: [BoardCoord] = []
            for g in groups {
                cells += g.cells.count
                primary = g.material
                cleared.append(contentsOf: g.cells.map { BoardCoord($0.0, $0.1) })
                for (x, y) in g.cells { state.board[x, y] = nil }
                state.recycledByMaterial[g.material, default: 0] += g.cells.count
                bumpOrderMaterial(g.material, amount: g.cells.count)
            }
            let sc = Scoring.recycleScore(cells: cells, groups: groups.count, level: state.level, chain: chain)
            let sp = Scoring.scrapForRecycle(groups: groups.count, cells: cells)
            state.score += sc
            state.runScrap += sp
            state.combo = chain
            state.lines += groups.count
            events.append(.recycled(groups: groups.count, cells: cells, score: sc, scrap: sp, material: primary, coords: cleared))
            applyGravity()
        }
        checkOrders()
        advanceLevelFromLines()
        return true
    }

    /// Once-per-run raccoon Snatch — remove one locked cell.
    @discardableResult
    public mutating func snatch(atX x: Int, y: Int) -> Bool {
        guard state.snatchAvailable, !state.over else { return false }
        guard state.board[x, y] != nil else { return false }
        state.board[x, y] = nil
        state.snatchAvailable = false
        events.append(.snatchUsed)
        applyGravity()
        // May trigger recycles after settle.
        resolveRecyclesOnly()
        return true
    }

    /// Snatch a random filled cell (autoplay / demo helper).
    @discardableResult
    public mutating func snatchRandom() -> Bool {
        var opts: [(Int, Int)] = []
        for y in state.board.config.hiddenRows..<state.board.config.rows {
            for x in 0..<state.board.config.cols {
                if state.board[x, y] != nil { opts.append((x, y)) }
            }
        }
        guard let pick = opts.randomElement() else { return false }
        return snatch(atX: pick.0, y: pick.1)
    }

    private mutating func resolveRecyclesOnly() {
        var chain = 0
        while true {
            let groups = RecycleMatcher.findGroups(on: state.board)
            guard !groups.isEmpty else { break }
            chain += 1
            var cells = 0
            var primary = groups[0].material
            var coords: [BoardCoord] = []
            for g in groups {
                cells += g.cells.count
                primary = g.material
                coords.append(contentsOf: g.cells.map { BoardCoord($0.0, $0.1) })
                for (x, y) in g.cells { state.board[x, y] = nil }
                state.recycledByMaterial[g.material, default: 0] += g.cells.count
                bumpOrderMaterial(g.material, amount: g.cells.count)
            }
            let score = Scoring.recycleScore(cells: cells, groups: groups.count, level: state.level, chain: chain)
            let scrap = Scoring.scrapForRecycle(groups: groups.count, cells: cells)
            state.score += score
            state.runScrap += scrap
            state.combo = chain
            state.lines += groups.count
            events.append(.recycled(groups: groups.count, cells: cells, score: score, scrap: scrap, material: primary, coords: coords))
            if chain >= 3 { bumpOrder(kind: .recycleChain, amount: chain) }
            applyGravity()
        }
        checkOrders()
        advanceLevelFromLines()
    }

    /// Level only climbs. Never recompute below the current level (shot seeds / mid-run).
    private mutating func advanceLevelFromLines() {
        let leveledBefore = state.level
        state.level = max(state.level, 1 + state.lines / 8)
        if state.level > leveledBefore {
            events.append(.leveledUp(state.level))
        }
    }

    /// Keep `lines` consistent with a staged level so the next clear cannot rewind it.
    private mutating func syncLinesFloorToLevel() {
        state.lines = max(state.lines, (state.level - 1) * 8)
    }

    private mutating func bumpOrderMaterial(_ mat: Material, amount: Int) {
        for i in state.orders.indices {
            guard !state.orders[i].done else { continue }
            if state.orders[i].kind == .recycleMaterial, state.orders[i].material == mat {
                state.orders[i].progress = min(state.orders[i].target, state.orders[i].progress + amount)
            }
            if state.orders[i].kind == .recycleAny {
                state.orders[i].progress = min(state.orders[i].target, state.orders[i].progress + amount)
            }
        }
    }

    private mutating func bumpOrder(kind: OrderTicket.Kind, amount: Int) {
        for i in state.orders.indices {
            guard !state.orders[i].done, state.orders[i].kind == kind else { continue }
            if kind == .recycleChain {
                state.orders[i].progress = max(state.orders[i].progress, amount)
            } else {
                state.orders[i].progress = min(state.orders[i].target, state.orders[i].progress + amount)
            }
        }
    }

    private var completedOrderIDs: Set<String> = []

    private mutating func checkOrders() {
        finalizeOrders()
    }

    private mutating func finalizeOrders() {
        for order in state.orders where order.done && !completedOrderIDs.contains(order.id) {
            completedOrderIDs.insert(order.id)
            events.append(.orderCompleted(order))
            state.score += 400
            state.runScrap += 8
        }
    }

    /// Evidence / UI helper — fill the press meter without slamming.
    public mutating func fillPressMeter() {
        state.pressMeter = state.pressMeterMax
    }

    /// FTUE / gym helper — set press meter without exposing `state` mutation.
    public mutating func setPressMeter(_ value: Int) {
        state.pressMeter = max(0, min(state.pressMeterMax, value))
    }

    public mutating func stash() {
        // Stash kept as optional hold bin — not required for Night Shift loop.
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

    public mutating func useMagnet() {
        // Deprecated — Snatch replaces magnet. No-op for API compat.
    }

    /// Autoplay: soft-ish play with occasional press / snatch.
    public mutating func autoplayStep() {
        guard !state.over else { return }
        if state.pressMeter >= state.pressMeterMax, Bool.random() {
            _ = slamPress()
            return
        }
        if state.snatchAvailable, placeCount > 6, Bool.random(), Bool.random() {
            _ = snatchRandom()
        }
        if Bool.random() { _ = tryRotate() }
        if Bool.random() { _ = tryMove(dx: Bool.random() ? 1 : -1, dy: 0) }
        // Prefer soft drops for readable video; hard drop less often.
        if Bool.random() {
            hardDrop()
        } else {
            for _ in 0..<3 { _ = softDrop() }
            if !(state.active.map { softDropFitsBelow($0) } ?? false) {
                hardDrop()
            }
        }
    }

    private func softDropFitsBelow(_ p: ActivePiece) -> Bool {
        var q = p
        q.y += 1
        return q.fits(state.board)
    }

    public mutating func drainEvents() -> [GameEvent] {
        finalizeOrders()
        let e = events
        events.removeAll()
        return e
    }

    /// Seed boards for App Store evidence shots.
    public mutating func applyShotScenario(_ shot: String) {
        state = GameState(config: state.board.config)
        events = []
        completedOrderIDs = []
        bag = RNGBag(seed: 0x5C01)
        placeCount = 0
        fillQueue()
        seedOrders(level: 2)
        let rows = state.board.config.rows
        let cols = state.board.config.cols
        let hid = state.board.config.hiddenRows

        switch shot {
        case "recycle":
            // Metal cluster of 6+ ready to read as a recycle beat.
            for y in (rows - 4)..<rows {
                for x in 0..<3 {
                    state.board[x, y] = Cell(piece: .can, material: .metal)
                }
            }
            state.board[1, rows - 5] = Cell(piece: .pipe, material: .metal)
            // Glass side clutter
            for y in (rows - 3)..<rows {
                state.board[5, y] = Cell(piece: .bottle, material: .glass)
                state.board[6, y] = Cell(piece: .bottle, material: .glass)
            }
            state.score = 4200
            state.combo = 2
            state.pressMeter = 5
            state.level = 3
            syncLinesFloorToLevel()
            state.active = ActivePiece(id: .can, x: 1, y: hid + 2)
        case "ftue":
            // Almost-cluster: 3 metal cans; active metal can completes the recycle.
            for x in 0..<3 {
                state.board[x, rows - 1] = Cell(piece: .can, material: .metal)
            }
            state.board[0, rows - 2] = Cell(piece: .can, material: .metal)
            state.board[1, rows - 2] = Cell(piece: .can, material: .metal)
            // Soft glass clutter away from the gift cluster.
            state.board[6, rows - 1] = Cell(piece: .bottle, material: .glass)
            state.board[7, rows - 1] = Cell(piece: .bottle, material: .glass)
            state.score = 0
            state.level = 1
            state.combo = 0
            state.pressMeter = 0
            state.snatchAvailable = false
            state.orders = [
                OrderTicket(id: "ftue-recycle", label: "Recycle metal once", kind: .recycleMaterial, target: 4, progress: 0, material: .metal),
            ]
            state.active = ActivePiece(id: .can, x: 3, y: hid + 4)
            state.queue = [.bottle, .plank]
        case "compactor", "press":
            // Bottom rows filled for a press slam showcase + meter full.
            for y in (rows - 2)..<rows {
                for x in 0..<cols {
                    let id: JunkID = [.can, .bottle, .plank, .tire, .crate, .pipe][(x + y) % 6]
                    state.board[x, y] = Cell(piece: id, material: JunkCatalog.def(for: id).material)
                }
            }
            // Mid clutter
            for y in (rows - 6)..<(rows - 2) {
                for x in 0..<cols where (x + y) % 3 != 0 {
                    let id: JunkID = [.can, .bentPipe, .plank, .tire][(x * 2 + y) % 4]
                    state.board[x, y] = Cell(piece: id, material: JunkCatalog.def(for: id).material)
                }
            }
            state.score = 7600
            state.level = 4
            syncLinesFloorToLevel()
            state.pressMeter = state.pressMeterMax
            state.combo = 1
            state.active = ActivePiece(id: .crate, x: 3, y: hid + 2)
        case "revive", "game-over":
            // Believable topped-out bin — dense solid tiles so the bin behind the
            // revive sheet still reads as a real game, not a gray void.
            let skyline = [14, 13, 15, 14, 16, 15, 14, 13]
            for x in 0..<cols {
                let fill = min(skyline[x % skyline.count], rows - hid)
                for i in 0..<fill {
                    let y = rows - 1 - i
                    let id: JunkID = [.can, .bottle, .plank, .pipe, .crate, .tire, .bentPipe, .fridge][(x * 5 + i * 3) % 8]
                    var cell = Cell(piece: id, material: JunkCatalog.def(for: id).material)
                    if i == 2, x == 3 { cell.sticky = true }
                    state.board[x, y] = cell
                }
            }
            // Overflow lip
            for x in 2..<6 {
                state.board[x, hid] = Cell(piece: .can, material: .metal)
            }
            // Smoke-only staged score for the revive sheet frame — live runs use natural top-out.
            state.score = 8800
            state.level = 6
            syncLinesFloorToLevel()
            state.over = true
            state.active = nil
            state.pressMeter = 3
            events.append(.gameOver)
        case "game", "gameplay":
            // Dense mid-run stack (~70% of visible rows) so the bin reads as a real
            // game — solid tiles + icons with high coverage, not a sparse bottom strip.
            let fillFrom = max(hid + 2, rows - 10)
            for y in fillFrom..<rows {
                for x in 0..<cols {
                    // Jagged skyline: leave a few air pockets, never a flat carpet.
                    let peak = fillFrom + ((x * 3 + 1) % 4)
                    if y < peak { continue }
                    if (x + y * 2) % 11 == 0 { continue }
                    let id: JunkID = [.can, .tire, .plank, .pipe, .crate, .bottle, .bentPipe][(x + y * 3) % 7]
                    state.board[x, y] = Cell(piece: id, material: JunkCatalog.def(for: id).material)
                }
            }
            state.score = 3180
            state.level = 3
            syncLinesFloorToLevel()
            state.combo = 1
            state.pressMeter = 6
            state.orders[0].progress = 7
            state.active = ActivePiece(id: .bottle, rot: 0, x: 3, y: hid + 1)
        case "demo", "autoplay":
            // Dense start so the bin climbs into real tension. Level 1 only climbs — never rewinds.
            for y in (rows - 7)..<rows {
                for x in 0..<cols where (x + y) % 5 != 0 {
                    let id: JunkID = [.can, .tire, .plank, .pipe, .crate, .bottle][(x + y) % 6]
                    state.board[x, y] = Cell(piece: id, material: JunkCatalog.def(for: id).material)
                }
            }
            // Seed a near-recycle metal pocket for an early satisfying clear.
            for y in (rows - 3)..<rows {
                state.board[0, y] = Cell(piece: .can, material: .metal)
                state.board[1, y] = Cell(piece: .pipe, material: .metal)
            }
            state.score = 0
            state.level = 1
            state.pressMeter = 4
            spawn()
        case "demo-nearmiss":
            // Jagged skyline kissing the overflow lip — readable near-miss.
            let skyline = [10, 11, 12, 11, 13, 12, 11, 10]
            for x in 0..<cols {
                let fill = min(skyline[x], rows - hid)
                for i in 0..<fill {
                    let y = rows - 1 - i
                    let id: JunkID = [.can, .bottle, .plank, .pipe, .crate, .tire, .bentPipe][(x * 5 + i * 3) % 7]
                    state.board[x, y] = Cell(piece: id, material: JunkCatalog.def(for: id).material)
                }
            }
            for x in 1..<5 {
                state.board[x, hid + 1] = Cell(piece: .can, material: .metal)
            }
            state.score = 12400
            state.level = 5
            syncLinesFloorToLevel()
            state.pressMeter = 7
            state.combo = 1
            state.active = ActivePiece(id: .plank, rot: 0, x: 3, y: hid + 2)
        case "daily":
            // Seeded daily board — identical for all players on the same UTC day.
            // Fill the board from the bag first, then rebuild the spawn queue so
            // preview[0] always matches the next spawn (never a stale bag peek).
            bag = RNGBag(seed: DailyDumpster.seed())
            for y in (rows - 5)..<rows {
                for x in 0..<cols where (x * 3 + y) % 4 != 0 {
                    let id = bag.next()
                    state.board[x, y] = Cell(piece: id, material: JunkCatalog.def(for: id).material)
                }
            }
            // Guaranteed near-cluster for fair first recycle.
            for x in 0..<3 {
                state.board[x, rows - 1] = Cell(piece: .can, material: .glass)
                state.board[x, rows - 2] = Cell(piece: .bottle, material: .glass)
            }
            state.score = 0
            state.level = 1
            state.pressMeter = 2
            seedOrders(level: 1)
            state.orders = [
                OrderTicket(id: "daily-glass", label: "Recycle 10 glass", kind: .recycleMaterial, target: 10, material: .glass),
                OrderTicket(id: "daily-press", label: "Slam the press", kind: .pressSlam, target: 1),
                OrderTicket(id: "daily-chain", label: "Make a 2× chain", kind: .recycleChain, target: 2),
            ]
            state.queue = []
            fillQueue()
            spawn()
        case "streak":
            // Presentation-only: empty board + high streak context via score field.
            state.score = 0
            state.level = 1
            spawn()
        case "snatch":
            // Gym: mid-board junk + Snatch available.
            applyShotScenario("game")
            state.snatchAvailable = true
            state.score = 2400
        case "tickets":
            // Gym: orders mid-progress for ticket VFX.
            applyShotScenario("game")
            if !state.orders.isEmpty {
                state.orders[0].progress = max(1, state.orders[0].target - 2)
            }
            if state.orders.count > 1 {
                state.orders[1].progress = state.orders[1].target
            }
        default:
            if let gym = BoardGym(rawValue: shot) {
                applyShotScenario(gym.shotName)
            } else {
                spawn()
            }
        }
    }

    /// Bottom-up material grid for Daily Dumpster share cards (visible rows).
    public func materialShareGrid() -> [[Material?]] {
        let hid = state.board.config.hiddenRows
        let vis = state.board.config.visibleRows
        var grid: [[Material?]] = []
        for y in hid..<(hid + vis) {
            var row: [Material?] = []
            for x in 0..<state.board.config.cols {
                row.append(state.board[x, y]?.material)
            }
            grid.append(row)
        }
        return grid
    }

    /// True when junk occupies the top visible lip rows (near-miss tension).
    public func isNearOverflow(threshold: Int = 3) -> Bool {
        let hid = state.board.config.hiddenRows
        for y in hid..<(hid + threshold) {
            for x in 0..<state.board.config.cols {
                if state.board[x, y] != nil { return true }
            }
        }
        return false
    }
}
