// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

#if canImport(SpriteKit)
import SpriteKit
import UIKit
import QuartzCore
import GameCore

/// SpriteKit playfield for Recycling Night Shift.
public final class CompactorScene: SKScene {
    public var engine = GameEngine(seed: UInt64.random(in: 1...UInt64.max))
    public var onGameOver: ((GameState) -> Void)?
    public var onEvents: (([GameEvent]) -> Void)?
    /// Fired when bandit mood changes so SwiftUI loops (idle/cheer/panic) stay in sync.
    public var onMood: ((RaccoonMood) -> Void)?
    public var autoplay = false
    /// Demo-only elapsed time for scripted near-miss → game-over beats.
    private var autoplayElapsed: TimeInterval = 0
    private var demoPhase: Int = 0
    public var preferredFPS: Int = 60
    public private(set) var measuredFPS: Double = 60
    public var raccoonMood: RaccoonMood = .idle
    public var feel: FeelConfig = ConfigLoader.feelOrFallback()

    public enum RaccoonMood: Equatable { case idle, cheer, panic, disco, gameOver }

    private var cellNodes: [[SKSpriteNode?]] = []
    private var activeNodes: [SKSpriteNode] = []
    private var activeRoot: SKNode?
    private var ghostRoot: SKNode?
    private var boardCrop: SKCropNode?
    private var fpsLabel: SKLabelNode?
    private var alleyNode: SKSpriteNode?
    private var pressPlate: SKSpriteNode?
    private var gravityAcc: TimeInterval = 0
    /// Continuous grounded timer (seconds) — not gravity-tick based.
    private var groundedElapsed: TimeInterval = 0
    /// Move/rotate resets of the lock timer; hard-locks at maxLockResets.
    private var lockResets: Int = 0
    private let maxLockResets = 15
    private var lastTime: TimeInterval = 0
    private var fpsSamples: [Double] = []
    private var didBuild = false
    /// Near-zero pad so solid tiles cover ≥85% of occupied cell area (QA coverage metric).
    private let cellPad: CGFloat = 0.0
    private var pendingShot: String?
    /// Continuous display coords (board space) — independent of discrete logic ticks.
    private var visualX: CGFloat = 0
    private var visualY: CGFloat = 0
    private var hasVisualPose = false
    private var snatchBusy = false
    /// Brief disco flash after a big combo clear.
    private var discoUntil: TimeInterval = 0
    private var cheerUntil: TimeInterval = 0

    private var touchStart: CGPoint?
    private var touchStartTime: TimeInterval = 0
    private var movedCols: Int = 0
    /// Accumulated finger delta in points for 1:1 column tracking.
    private var dragAccumX: CGFloat = 0
    private var softDragging = false

    /// Small toast text for SwiftUI banner (not big mid-board labels).
    public var onToast: ((String) -> Void)?
    /// Soft click when a piece snaps left/right/rotate (SFX/haptic live in the app shell).
    public var onPieceSnap: (() -> Void)?
    /// Fired once after the first real board paint (dark fill + cells — never blank gray).
    /// May be assigned after `didMove`; fires immediately if the board is already ready.
    public var onFirstGameFrame: (() -> Void)? {
        didSet { noteFirstGameFrame() }
    }
    private var didFireFirstGameFrame = false
    private var lastFlashAt: TimeInterval = 0
    private var nearMissSignature: String = ""

    public override func didMove(to view: SKView) {
        let charcoal = SKColor(red: 0.05, green: 0.06, blue: 0.10, alpha: 1)
        backgroundColor = charcoal
        view.backgroundColor = charcoal
        preferredFPS = 60
        view.preferredFramesPerSecond = preferredFPS
        view.ignoresSiblingOrder = true
        view.isMultipleTouchEnabled = false
        // Paint the dark bin + solid tiles FIRST (no gray flash). Sync-warm critical art.
        _ = tex("BinInterior")
        _ = tex("DumpsterFrame")
        _ = tex("AlleyBackground")
        _ = tex("CellPlate")
        _ = tex("Slam01")
        _ = tex("Slam02")
        _ = tex("ClearBurst")
        for name in Self.requiredJunkTextureNames {
            _ = JunkTextureLoader.texture(named: name)
        }
        for mat in Material.allCases {
            _ = representativeTexture(for: mat)
            _ = ghostPlateTexture(for: mat)
        }
        rebuild()
    }

    private func noteFirstGameFrame() {
        guard didBuild, !didFireFirstGameFrame, let cb = onFirstGameFrame else { return }
        didFireFirstGameFrame = true
        cb()
    }

    public override func didChangeSize(_ oldSize: CGSize) {
        if size.width > 10, size.height > 10, size != oldSize {
            rebuild()
        }
    }

    public func configureForProMotion(_ enabled: Bool) {
        preferredFPS = 60
        view?.preferredFramesPerSecond = preferredFPS
    }

    public func reset(seed: UInt64 = UInt64.random(in: 1...999_999)) {
        engine = GameEngine(seed: seed)
        gravityAcc = 0
        groundedElapsed = 0
        lockResets = 0
        clearTouchState()
        raccoonMood = .idle
        discoUntil = 0
        cheerUntil = 0
        render(immediate: true)
    }

    /// TRASH TALK: queue incoming junk rows (warning meter, then land).
    public func queueJunk(rows: Int) {
        engine.queueJunk(rows: rows)
        handleEvents()
        render(immediate: false)
    }

    @discardableResult
    public func tickJunkWarning(dt: Double) -> Bool {
        let landed = engine.tickJunkWarning(dt: dt)
        if landed || engine.state.pendingJunkRows > 0 {
            handleEvents()
            render(immediate: false)
        }
        return landed
    }

    public func applyShot(_ shot: String) {
        pendingShot = shot
        engine.applyShotScenario(shot)
        gravityAcc = 0
        groundedElapsed = 0
        lockResets = 0
        clearTouchState()
        if shot == "recycle" { raccoonMood = .cheer }
        else if shot == "compactor" || shot == "press" { raccoonMood = .cheer }
        else if shot == "revive" || shot == "game-over" { raccoonMood = .gameOver }
        else { raccoonMood = .idle }
        if didBuild {
            render(immediate: true)
            presentPendingShotJuice()
        }
    }

    /// Continuous autoplay demo — soft prompts only; game-over must come from the live run.
    public func startDemoChoreography(onGameOverBeat: @escaping () -> Void) {
        autoplay = true
        autoplayElapsed = 0
        demoPhase = 0
        removeAction(forKey: "demoChoreography")
        run(SKAction.sequence([
            // Early SLAM so a ~45s smoke clip always shows the press beat.
            SKAction.wait(forDuration: 8),
            SKAction.run { [weak self] in
                guard let self, !self.engine.state.over else { return }
                self.engine.fillPressMeter()
                _ = self.engine.slamPress()
                self.handleEvents()
                self.render(immediate: false)
            },
            SKAction.wait(forDuration: 6),
            SKAction.run { [weak self] in
                guard let self, !self.engine.state.over else { return }
                if self.engine.state.snatchAvailable {
                    _ = self.engine.snatchRandom()
                    self.handleEvents()
                    self.render(immediate: false)
                }
            },
            // Poll until natural top-out; never force a score/level swap.
            SKAction.repeat(SKAction.sequence([
                SKAction.wait(forDuration: 1.0),
                SKAction.run { [weak self] in
                    guard let self else { return }
                    if self.engine.state.over {
                        self.removeAction(forKey: "demoChoreography")
                        onGameOverBeat()
                    }
                },
            ]), count: 90),
        ]), withKey: "demoChoreography")
    }

    private func presentPendingShotJuice() {
        guard let shot = pendingShot else { return }
        if shot == "compactor" || shot == "press" {
            presentPressMoment()
        } else if shot == "recycle" {
            presentRecycleMoment()
        }
    }

    private func tex(_ name: String) -> SKTexture? {
        JunkTextureLoader.texture(named: name)
    }

    nonisolated public static var requiredJunkTextureNames: [String] {
        JunkCatalog.all.map(\.textureName)
    }

    private func rebuild() {
        removeAllChildren()
        cellNodes = []
        activeNodes = []
        activeRoot = nil
        ghostRoot?.removeFromParent()
        ghostRoot = nil
        boardCrop = nil
        alleyNode = nil
        pressPlate = nil
        fpsLabel = nil
        didBuild = false
        guard size.width > 10, size.height > 10 else { return }

        if let alleyTex = tex("AlleyBackground") {
            let alley = SKSpriteNode(texture: alleyTex)
            let scale = max(size.width / max(1, alley.size.width), size.height / max(1, alley.size.height))
            alley.size = CGSize(width: alley.size.width * scale, height: alley.size.height * scale)
            alley.position = CGPoint(x: size.width / 2, y: size.height / 2)
            alley.zPosition = -30
            alley.alpha = 0.55
            addChild(alley)
            alleyNode = alley
        }
        let wash = SKSpriteNode(color: SKColor(red: 0.02, green: 0.02, blue: 0.08, alpha: 0.45), size: size)
        wash.position = CGPoint(x: size.width / 2, y: size.height / 2)
        wash.zPosition = -25
        addChild(wash)

        let cols = engine.state.board.config.cols
        let vis = engine.state.board.config.visibleRows
        cellNodes = Array(repeating: Array(repeating: nil, count: cols), count: vis)
        let cs = cellSize()
        let origin = gridOrigin()
        let gridW = cs.width * CGFloat(cols)
        let gridH = cs.height * CGFloat(vis)

        if let frameTex = tex("DumpsterFrame") {
            let frame = SKSpriteNode(texture: frameTex)
            // Tight frame around the grid — no huge empty dumpster margin.
            frame.size = CGSize(width: gridW + cs.width * 0.22, height: gridH + cs.height * 0.35)
            frame.position = CGPoint(x: origin.x + gridW / 2, y: origin.y + gridH / 2 - cs.height * 0.02)
            frame.zPosition = 0
            addChild(frame)
        } else {
            let frame = SKShapeNode(rectOf: CGSize(width: gridW + 8, height: gridH + 8), cornerRadius: 10)
            frame.strokeColor = SKColor(red: 0, green: 0.95, blue: 1, alpha: 0.75)
            frame.fillColor = SKColor(red: 0.04, green: 0.05, blue: 0.09, alpha: 0.55)
            frame.lineWidth = 3
            frame.position = CGPoint(x: origin.x + gridW / 2, y: origin.y + gridH / 2)
            addChild(frame)
        }

        // Slim neon rails hug the grid — no wide empty dumpster side space.
        for side in [-1, 1] {
            let rail = SKSpriteNode(
                color: SKColor(red: 0.95, green: 0.2, blue: 0.75, alpha: 0.7),
                size: CGSize(width: max(3, cs.width * 0.06), height: gridH)
            )
            rail.position = CGPoint(
                x: origin.x + gridW / 2 + CGFloat(side) * (gridW / 2 + rail.size.width * 0.6),
                y: origin.y + gridH / 2
            )
            rail.zPosition = 2
            addChild(rail)
        }

        // Crop cells + active piece to the bin's inner rectangle (never over the frame).
        let crop = SKCropNode()
        crop.zPosition = 3
        let inset: CGFloat = 6
        let mask = SKSpriteNode(
            color: .white,
            size: CGSize(width: gridW - inset, height: gridH - inset)
        )
        mask.position = CGPoint(x: origin.x + gridW / 2, y: origin.y + gridH / 2)
        crop.maskNode = mask
        addChild(crop)
        boardCrop = crop

        // Bin-interior board backdrop (Higgsfield) — never flat gray while textures load.
        let boardSize = CGSize(width: gridW - inset, height: gridH - inset)
        let boardFill: SKSpriteNode
        if let binTex = tex("BinInterior") {
            boardFill = SKSpriteNode(texture: binTex, size: boardSize)
            boardFill.color = .white
            boardFill.colorBlendFactor = 0
        } else {
            boardFill = SKSpriteNode(
                color: SKColor(red: 0.05, green: 0.06, blue: 0.10, alpha: 1),
                size: boardSize
            )
        }
        boardFill.position = CGPoint(x: origin.x + gridW / 2, y: origin.y + gridH / 2)
        boardFill.zPosition = 0
        boardFill.name = "binInterior"
        crop.addChild(boardFill)

        // Faint grid lines so stacking reads without fighting the neon rim.
        let gridOverlay = SKNode()
        gridOverlay.zPosition = 0.5
        gridOverlay.name = "faintGrid"
        for x in 0...cols {
            let line = SKSpriteNode(
                color: SKColor(white: 1, alpha: 0.06),
                size: CGSize(width: 1, height: gridH - inset)
            )
            line.position = CGPoint(
                x: origin.x + cs.width * CGFloat(x),
                y: origin.y + gridH / 2
            )
            gridOverlay.addChild(line)
        }
        for y in 0...vis {
            let line = SKSpriteNode(
                color: SKColor(white: 1, alpha: 0.06),
                size: CGSize(width: gridW - inset, height: 1)
            )
            line.position = CGPoint(
                x: origin.x + gridW / 2,
                y: origin.y + cs.height * CGFloat(y)
            )
            gridOverlay.addChild(line)
        }
        crop.addChild(gridOverlay)

        let plateTex = tex("CellPlate")
        for y in 0..<vis {
            for x in 0..<cols {
                // Parent = rounded material plate; child icon overlays (~58% of cell).
                let n: SKSpriteNode
                if let plateTex {
                    n = SKSpriteNode(texture: plateTex, size: CGSize(width: cs.width - cellPad, height: cs.height - cellPad))
                    n.color = SKColor(white: 1, alpha: 0.04)
                    n.colorBlendFactor = 1
                } else {
                    n = SKSpriteNode(
                        color: SKColor(white: 1, alpha: 0.04),
                        size: CGSize(width: cs.width - cellPad, height: cs.height - cellPad)
                    )
                }
                n.position = positionFor(x: x, boardY: y + engine.state.board.config.hiddenRows)
                n.zPosition = 1
                n.name = "cell"
                let icon = SKSpriteNode(color: .clear, size: CGSize(width: (cs.width - cellPad) * 0.58, height: (cs.height - cellPad) * 0.58))
                icon.name = "icon"
                icon.zPosition = 2
                n.addChild(icon)
                crop.addChild(n)
                cellNodes[y][x] = n
            }
        }

        for i in 0..<22 {
            let drop = SKSpriteNode(
                color: SKColor(white: 0.85, alpha: 0.28),
                size: CGSize(width: 1.8, height: CGFloat.random(in: 14...26))
            )
            drop.position = CGPoint(x: CGFloat.random(in: 0...size.width), y: CGFloat.random(in: 0...size.height))
            drop.zPosition = -8
            addChild(drop)
            let fall = SKAction.moveBy(x: -10, y: -size.height - 40, duration: Double.random(in: 0.55...1.0))
            let reset = SKAction.run { [weak drop, weak self] in
                guard let drop, let self else { return }
                drop.position = CGPoint(x: CGFloat.random(in: 0...self.size.width), y: self.size.height + 12)
            }
            drop.run(SKAction.repeatForever(SKAction.sequence([fall, reset])))
            drop.alpha = i % 2 == 0 ? 0.4 : 0.2
        }

        if let alleyNode {
            alleyNode.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.moveBy(x: 8, y: 4, duration: 4.5),
                SKAction.moveBy(x: -8, y: -4, duration: 4.5),
            ])))
        }

        // Visible per-material recycle chutes (right of bin).
        let chuteMats: [(Material, SKColor)] = [
            (.metal, SKColor(red: 0.55, green: 0.7, blue: 0.85, alpha: 1)),
            (.plastic, SKColor(red: 0.95, green: 0.2, blue: 0.75, alpha: 1)),
            (.glass, SKColor(red: 0.15, green: 0.9, blue: 0.95, alpha: 1)),
            (.paper, SKColor(red: 0.9, green: 0.7, blue: 0.35, alpha: 1)),
        ]
        for (i, pair) in chuteMats.enumerated() {
            let mouth = SKShapeNode(rectOf: CGSize(width: cs.width * 0.7, height: cs.height * 1.1), cornerRadius: 6)
            mouth.fillColor = pair.1.withAlphaComponent(0.35)
            mouth.strokeColor = pair.1
            mouth.lineWidth = 2
            mouth.position = chutePoint(for: pair.0)
            // chutePoint needs board; temporarily place by index until engine ready — recompute after grid.
            mouth.position = CGPoint(
                x: origin.x + gridW + cs.width * 0.55,
                y: origin.y + cs.height * (3.5 + CGFloat(i) * 2.2)
            )
            mouth.zPosition = 5
            mouth.name = "chute-\(pair.0.rawValue)"
            addChild(mouth)
            let tag = SKLabelNode(fontNamed: "AvenirNext-Bold")
            // Two-letter labels (ME/PL/GL/PA) ≥ 11 pt — single letters collide (two "P"s).
            let two: String = {
                switch pair.0 {
                case .metal: return "ME"
                case .plastic: return "PL"
                case .glass: return "GL"
                case .paper: return "PA"
                }
            }()
            tag.text = two
            tag.fontSize = 11
            tag.fontColor = pair.1
            tag.verticalAlignmentMode = .center
            tag.horizontalAlignmentMode = .center
            tag.position = .zero
            mouth.addChild(tag)
        }

        // Mechanical press plate (rests above the bin until slam).
        let plateW = cs.width * CGFloat(cols) + 18
        let plate = SKSpriteNode(color: SKColor(red: 0.72, green: 0.78, blue: 0.88, alpha: 1), size: CGSize(width: plateW, height: max(14, cs.height * 0.55)))
        plate.position = CGPoint(x: origin.x + cs.width * CGFloat(cols) / 2, y: origin.y + gridH + cs.height * 1.2)
        plate.zPosition = 40
        let lip = SKSpriteNode(color: SKColor(red: 1, green: 0.35, blue: 0.85, alpha: 0.85), size: CGSize(width: plateW, height: 3))
        lip.position = CGPoint(x: 0, y: -plate.size.height * 0.45)
        plate.addChild(lip)
        addChild(plate)
        pressPlate = plate

        if ProcessInfo.processInfo.arguments.contains("-showFPS") {
            let fps = SKLabelNode(fontNamed: "Menlo-Bold")
            fps.fontSize = 10
            fps.fontColor = SKColor(white: 1, alpha: 0.35)
            fps.horizontalAlignmentMode = .left
            fps.position = CGPoint(x: 10, y: 8)
            fps.zPosition = 50
            fps.text = "60 fps"
            addChild(fps)
            fpsLabel = fps
        }

        didBuild = true
        render(immediate: true)
        presentPendingShotJuice()
        noteFirstGameFrame()
    }

    private func cellSize() -> CGSize {
        let cols = CGFloat(engine.state.board.config.cols)
        // Nearly full SpriteView width — height letterboxing left a ~40% empty bar above.
        let s = size.width * 0.995 / cols
        return CGSize(width: s, height: s)
    }

    private func gridOrigin() -> CGPoint {
        let cs = cellSize()
        let cols = CGFloat(engine.state.board.config.cols)
        let rows = CGFloat(engine.state.board.config.visibleRows)
        let totalW = cs.width * cols
        let totalH = cs.height * rows
        // Top-align the bin — drop the empty horizontal bar above the playfield.
        let topPad = max(4, cs.height * 0.08)
        return CGPoint(
            x: (size.width - totalW) / 2,
            y: max(0, size.height - totalH - topPad)
        )
    }

    private func positionFor(x: Int, boardY: Int, yOffset: CGFloat = 0) -> CGPoint {
        let cs = cellSize()
        let origin = gridOrigin()
        let hid = engine.state.board.config.hiddenRows
        let visY = boardY - hid
        return CGPoint(
            x: origin.x + cs.width * (CGFloat(x) + 0.5),
            y: origin.y + cs.height * (CGFloat(engine.state.board.config.visibleRows - 1 - visY) + 0.5) + yOffset
        )
    }

    public override func update(_ currentTime: TimeInterval) {
        var dt: CGFloat = 1.0 / 60.0
        if lastTime > 0 {
            let raw = currentTime - lastTime
            if raw > 0, raw < 1 {
                dt = CGFloat(raw)
                let fps = min(144, 1.0 / raw)
                fpsSamples.append(fps)
                if fpsSamples.count > 30 { fpsSamples.removeFirst() }
                measuredFPS = fpsSamples.reduce(0, +) / Double(fpsSamples.count)
                fpsLabel?.text = String(format: "%.0f fps", measuredFPS)
            }
        }
        lastTime = currentTime

        let nextMood = computeRaccoonMood()
        if nextMood != raccoonMood {
            raccoonMood = nextMood
            onMood?(nextMood)
        }

        // TRASH TALK junk warning → land (no-op when pendingJunkRows == 0).
        if engine.state.pendingJunkRows > 0 {
            _ = engine.tickJunkWarning(dt: Double(dt))
            handleEvents()
        }

        // Continuous visual smoothing toward discrete logic pose.
        smoothActivePose(dt: dt)

        if autoplay {
            // Never stay paused during demo — smoke recordVideo must show live motion.
            if isPaused { isPaused = false }
            autoplayElapsed += TimeInterval(dt)
            // Live-run tension only — never applyShotScenario mid-demo (that rolled level/score backwards).
            if demoPhase == 0, engine.isNearOverflow(threshold: feel.nearMissRows) {
                demoPhase = 1
                onToast?("SO CLOSE")
                raccoonMood = .panic
            }
            // Faster cadence so a ~45s clip shows locks, clears, and SLAM.
            gravityAcc += Double(dt)
            if gravityAcc > 0.14 {
                gravityAcc = 0
                if !engine.state.over {
                    engine.autoplayStep()
                    handleEvents()
                }
                if engine.state.over {
                    demoPhase = 2
                    onGameOver?(engine.state)
                }
                render(immediate: false)
            }
            return
        }
        guard !engine.state.over, engine.state.active != nil else { return }
        // Speeds up every level; floor keeps it readable.
        let grav = max(feel.gravityMinSec, feel.gravityBaseSec - Double(engine.state.level) * feel.gravityLevelStep)
        // Level 6+: rare alley gust nudges the active piece sideways.
        if engine.state.level >= LevelTwist.alleyGusts.rawValue, Int.random(in: 0...240) == 0 {
            let dir = Bool.random() ? 1 : -1
            if noteLockResetMove({ engine.tryMove(dx: dir, dy: 0) }) {
                snapActivePose()
                onPieceSnap?()
                onToast?("Gust!")
            }
        }
        // Continuous grounded lock timer — never depends on a latched soft-drop button.
        tickGroundedLock(dt: Double(dt))
        gravityAcc += Double(dt)
        if gravityAcc >= grav {
            gravityAcc = 0
            if engine.softDrop() {
                groundedElapsed = 0
            }
            render(immediate: false)
        }
        // Soft-drag (slow finger down) — one cell at a time, never latches after touch loss.
        if softDragging {
            _ = engine.softDrop()
            if engine.isGrounded() {
                softDragging = false
            }
            render(immediate: false)
        }
    }

    private func tickGroundedLock(dt: Double) {
        guard engine.state.active != nil, !engine.state.over else {
            groundedElapsed = 0
            lockResets = 0
            return
        }
        guard engine.isGrounded() else {
            groundedElapsed = 0
            return
        }
        groundedElapsed += dt
        let lockNeed = engine.lockDelaySeconds(base: feel.lockDelaySec)
        if groundedElapsed >= lockNeed || lockResets >= maxLockResets {
            forceLock()
        }
    }

    private func forceLock(hard: Bool = false) {
        groundedElapsed = 0
        lockResets = 0
        softDragging = false
        clearTouchState()
        engine.lock(hard: hard)
        handleEvents()
        hasVisualPose = false
        render(immediate: false)
        if engine.state.over { onGameOver?(engine.state) }
    }

    /// Move/rotate while grounded burns one lock reset; at the cap we hard-settle.
    @discardableResult
    private func noteLockResetMove(_ body: () -> Bool) -> Bool {
        let wasGrounded = engine.isGrounded()
        let ok = body()
        guard ok else { return false }
        if wasGrounded || engine.isGrounded() {
            lockResets += 1
            groundedElapsed = 0
            if lockResets >= maxLockResets {
                forceLock()
            }
        }
        return true
    }

    private func clearTouchState() {
        touchStart = nil
        dragAccumX = 0
        movedCols = 0
        softDragging = false
    }

    private func smoothActivePose(dt: CGFloat) {
        guard let p = engine.state.active else {
            hasVisualPose = false
            return
        }
        let targetX = CGFloat(p.x)
        let targetY = CGFloat(p.y)
        if !hasVisualPose {
            visualX = targetX
            visualY = targetY
            hasVisualPose = true
        } else {
            // Lateral ease; vertical chase with a bit of lag for continuous fall.
            let lx = min(1, dt * CGFloat(feel.fallLerpLateral))
            let ly = min(1, dt * CGFloat(feel.fallLerpVertical))
            visualX += (targetX - visualX) * lx
            visualY += (targetY - visualY) * ly
        }
        layoutActiveNodes()
    }

    private func handleEvents() {
        let ev = engine.drainEvents()
        for e in ev {
            switch e {
            case .locked(let hard):
                // Soft settle vs hard slam — slam gets press-tier shake + more debris.
                let lockPt = positionFor(x: Int(visualX.rounded()), boardY: max(0, Int(visualY.rounded())))
                let debris = hard ? 18 : 9
                let sparks = hard ? 12 : 6
                spawnParticle(named: "DebrisMetal", at: lockPt, count: debris)
                spawnParticle(named: hard ? "DebrisNeon" : "SparkTeal", at: lockPt, count: sparks)
                screenShake(strength: hard ? CGFloat(feel.shakePress) * 0.9 : 5.5)
                // Every land gets a readable squash — soft lands too, not only slams.
                bounceLandedCells(around: lockPt, hard: hard)
                if hard {
                    let pieceW = cellSize().width * CGFloat(max(1, engine.state.active?.def.rotations.first?.count ?? 2))
                    presentSlamBurst(at: lockPt, pieceWidth: max(cellSize().width * 2.2, pieceW * 1.35))
                    boardFlash(color: SKColor(red: 1, green: 0.95, blue: 0.75, alpha: 0.6))
                    hitStop(seconds: feel.hitStopShortSec * 0.85)
                } else {
                    hitStop(seconds: feel.hitStopShortSec * 0.35)
                }
                clearGhost()
                hasVisualPose = false
            case .recycled(_, let cells, let score, _, let material, let coords):
                // Snapshot textures BEFORE render clears the cells (real item ghosts, not flat squares).
                // If lock→recycle happened before a paint, synthesize solid+icon from material.
                var snaps = snapshotCellLooks(coords: coords)
                let cs = cellSize()
                let fallbackSize = CGSize(width: cs.width - cellPad, height: cs.height - cellPad)
                for c in coords {
                    let prior = snaps[c]
                    let solid = fallbackColor(material)
                    // Force a material icon if the cell hadn't painted yet (cold warm).
                    let icon = prior?.texture ?? representativeTexture(for: material)
                        ?? JunkTextureLoader.texture(named: JunkCatalog.textureName(
                            for: JunkCatalog.all.first(where: { $0.material == material })?.id ?? .can
                        ))
                    snaps[c] = CellLook(
                        texture: icon,
                        size: prior?.size ?? fallbackSize,
                        color: solid,
                        blend: 0
                    )
                }
                let combo = max(1, engine.state.combo)
                presentClearBurst(across: coords)
                recycleSuck(coords: coords, material: material, points: score, combo: combo, snaps: snaps)
                subtleGlow(color: materialGlow(material))
                boardFlash(color: materialGlow(material).withAlphaComponent(0.75 + min(0.2, CGFloat(combo) * 0.04)))
                let shakeMul = 1.0 + min(1.2, Double(combo - 1) * 0.28)
                // Shake scales with lines/combo — crunch without covering the bin.
                screenShake(strength: CGFloat(feel.shakeRecycle) * shakeMul * (1 + Double(min(4, cells)) * 0.08))
                hitStop(seconds: 0.06)
                if combo >= 3 {
                    discoUntil = CACurrentMediaTime() + 1.1
                    raccoonMood = .disco
                    presentComboBanner(combo: combo)
                    presentComboRing(combo: combo)
                    onToast?("CHAIN ×\(combo)")
                } else if combo >= 2 {
                    presentComboBanner(combo: combo)
                    presentComboRing(combo: combo)
                    onToast?("CHAIN ×\(combo)")
                    cheerUntil = CACurrentMediaTime() + 1.2
                    raccoonMood = .cheer
                } else {
                    onToast?("RECYCLE +\(score)")
                    cheerUntil = CACurrentMediaTime() + 1.0
                    raccoonMood = .cheer
                }
                // Score popups beside the board (not over the falling area).
                spawnScorePipsBesideBoard(points: score)
                spawnParticle(
                    named: combo >= 3 ? "SparkMagenta" : "SparkTeal",
                    at: coords.first.map { positionFor(x: $0.x, boardY: $0.y) } ?? CGPoint(x: size.width * 0.5, y: size.height * 0.45),
                    count: min(52, 14 + cells * 2 + combo * 4)
                )
                _ = cells
            case .pressed(let cells, _, _):
                animatePressPlate(cells: cells)
                cheerUntil = CACurrentMediaTime() + 1.2
                raccoonMood = .cheer
                onToast?("Press slam")
            case .orderCompleted(let order):
                onToast?("Order done · \(order.label)")
            case .snatchUsed:
                playSnatchGrab()
                onToast?("Snatch!")
            case .leveledUp(let lvl):
                onToast?(LevelTwist.active(at: lvl).toastTitle)
            case .spawned:
                hasVisualPose = false
                updateLandingGhost()
            case .gameOver:
                clearGhost()
                raccoonMood = .gameOver
            default: break
            }
        }
        onEvents?(ev)
    }

    private func bounceLandedCells(around point: CGPoint, hard: Bool) {
        let radius: CGFloat = hard ? 90 : 55
        let amp: CGFloat = hard ? 0.22 : 0.12
        for row in cellNodes {
            for node in row {
                guard let node, node.alpha > 0.2 else { continue }
                let d = hypot(node.position.x - point.x, node.position.y - point.y)
                guard d < radius else { continue }
                node.removeAction(forKey: "landBounce")
                let squash = SKAction.sequence([
                    SKAction.group([
                        SKAction.scaleX(to: 1.0 + amp, duration: 0.05),
                        SKAction.scaleY(to: 1.0 - amp, duration: 0.05),
                    ]),
                    SKAction.group([
                        SKAction.scaleX(to: 1.0 - amp * 0.4, duration: 0.06),
                        SKAction.scaleY(to: 1.0 + amp * 0.35, duration: 0.06),
                    ]),
                    SKAction.scale(to: 1.0, duration: 0.07),
                ])
                node.run(squash, withKey: "landBounce")
            }
        }
    }

    private func presentComboRing(combo: Int) {
        let origin = gridOrigin()
        let cs = cellSize()
        let cols = CGFloat(engine.state.board.config.cols)
        let rows = CGFloat(engine.state.board.config.visibleRows)
        let ring = SKShapeNode(rectOf: CGSize(width: cs.width * cols + 10, height: cs.height * rows + 10), cornerRadius: 10)
        ring.strokeColor = combo >= 4
            ? SKColor(red: 1, green: 0.3, blue: 0.85, alpha: 1)
            : SKColor(red: 0.1, green: 1, blue: 0.9, alpha: 1)
        ring.lineWidth = 3 + CGFloat(min(4, combo))
        ring.fillColor = .clear
        ring.glowWidth = 6
        ring.position = CGPoint(x: origin.x + cs.width * cols / 2, y: origin.y + cs.height * rows / 2)
        ring.zPosition = 49
        ring.alpha = 0
        addChild(ring)
        ring.run(SKAction.sequence([
            SKAction.group([
                SKAction.fadeAlpha(to: 0.95, duration: 0.06),
                SKAction.scale(to: 1.04, duration: 0.1),
            ]),
            SKAction.group([
                SKAction.fadeOut(withDuration: 0.28),
                SKAction.scale(to: 1.12, duration: 0.28),
            ]),
            SKAction.removeFromParent(),
        ]))
    }

    private func clearGhost() {
        ghostRoot?.removeFromParent()
        ghostRoot = nil
    }

    private func updateLandingGhost() {
        guard let p = engine.state.active, !engine.state.over else {
            clearGhost()
            return
        }
        let landY = p.landingY(on: engine.state.board)
        // Hide ghost when already resting / one cell above land (noise).
        if landY <= p.y + 1 {
            clearGhost()
            return
        }
        let tag = "ghost-\(p.id.rawValue)-\(p.rot)-\(p.x)-\(landY)"
        if ghostRoot?.name == tag { return }
        clearGhost()
        let root = SKNode()
        root.name = tag
        root.zPosition = 4
        // Brighter landing ghost so the drop target reads on a phone at arm's length.
        root.alpha = 0.55
        (boardCrop ?? self).addChild(root)
        ghostRoot = root
        let cs = cellSize()
        let mat = p.def.material
        let color = plateColor(for: p.id, material: mat).withAlphaComponent(0.72)
        do {
            let shape = p.def.rotations[p.rot % p.def.rotations.count]
            for off in shape {
                let n = SKSpriteNode(color: color, size: CGSize(width: cs.width - cellPad, height: cs.height - cellPad))
                n.position = CGPoint(x: CGFloat(off[0]) * cs.width, y: -CGFloat(off[1]) * cs.height)
                root.addChild(n)
            }
        }
        root.position = positionForBoard(x: CGFloat(p.x), y: CGFloat(landY))
    }

    private func subtleGlow(color: SKColor) {
        let glow = SKSpriteNode(color: color, size: CGSize(width: size.width * 0.7, height: 36))
        glow.position = CGPoint(x: size.width / 2, y: gridOrigin().y + cellSize().height * CGFloat(engine.state.board.config.visibleRows) + 8)
        glow.zPosition = 44
        glow.alpha = 0
        addChild(glow)
        glow.run(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.55, duration: 0.08),
            SKAction.fadeOut(withDuration: 0.28),
            SKAction.removeFromParent(),
        ]))
    }

    private func boardFlash(color: SKColor) {
        let now = CACurrentMediaTime()
        guard now - lastFlashAt >= feel.flashCooldownSec else { return }
        lastFlashAt = now
        let origin = gridOrigin()
        let cs = cellSize()
        let cols = CGFloat(engine.state.board.config.cols)
        let rows = CGFloat(engine.state.board.config.visibleRows)
        let flash = SKSpriteNode(
            color: color,
            size: CGSize(width: cs.width * cols - 4, height: cs.height * rows - 4)
        )
        flash.position = CGPoint(x: origin.x + cs.width * cols / 2, y: origin.y + cs.height * rows / 2)
        flash.zPosition = 48
        flash.alpha = 0
        flash.blendMode = .add
        addChild(flash)
        flash.run(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.85, duration: 0.04),
            SKAction.fadeOut(withDuration: 0.18),
            SKAction.removeFromParent(),
        ]))
    }

    private func presentComboBanner(combo: Int) {
        let banner = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        banner.text = combo >= 5 ? "MEGA CHAIN ×\(combo)" : (combo >= 3 ? "CHAIN ×\(combo)" : "CHAIN ×\(combo)")
        banner.fontSize = combo >= 5 ? 42 : (combo >= 3 ? 36 : 30)
        banner.fontColor = combo >= 5
            ? SKColor(red: 1, green: 0.35, blue: 0.85, alpha: 1)
            : (combo >= 3
               ? SKColor(red: 0.2, green: 1, blue: 0.85, alpha: 1)
               : SKColor(red: 0.95, green: 0.95, blue: 1, alpha: 1))
        banner.position = CGPoint(x: size.width * 0.5, y: size.height * 0.58)
        banner.zPosition = 90
        banner.setScale(0.45)
        banner.alpha = 0
        addChild(banner)
        let hold = min(1.1, 0.45 + Double(combo) * 0.08)
        banner.run(SKAction.sequence([
            SKAction.group([
                SKAction.fadeAlpha(to: 1, duration: 0.08),
                SKAction.scale(to: combo >= 5 ? 1.35 : 1.18, duration: 0.14),
            ]),
            SKAction.wait(forDuration: hold),
            SKAction.group([
                SKAction.fadeOut(withDuration: 0.2),
                SKAction.scale(to: 0.8, duration: 0.2),
            ]),
            SKAction.removeFromParent(),
        ]))
    }

    private func snapActivePose() {
        guard let p = engine.state.active else { return }
        visualX = CGFloat(p.x)
        visualY = CGFloat(p.y)
        hasVisualPose = true
        layoutActiveNodes()
    }

    public func presentPressMoment() {
        engine.fillPressMeter()
        animatePressPlate(cells: 16)
        onToast?("Press slam")
    }

    public func presentRecycleMoment() {
        let hid = engine.state.board.config.hiddenRows
        let vis = engine.state.board.config.visibleRows
        var coords: [BoardCoord] = []
        for y in 0..<vis {
            for x in 0..<engine.state.board.config.cols {
                guard let cell = engine.state.board[x, y + hid], cell.material == .metal else { continue }
                coords.append(BoardCoord(x, y + hid))
                if let node = cellNodes[y][x] {
                    let glow = SKSpriteNode(
                        color: SKColor(red: 0.1, green: 1, blue: 0.85, alpha: 0.55),
                        size: CGSize(width: node.size.width + 8, height: node.size.height + 8)
                    )
                    glow.name = "recycleHoldGlow"
                    glow.position = node.position
                    glow.zPosition = 7
                    addChild(glow)
                    // Hold the glow long enough for smoke capture (do not vanish at suck end).
                    glow.run(SKAction.repeatForever(SKAction.sequence([
                        SKAction.fadeAlpha(to: 0.25, duration: 0.25),
                        SKAction.fadeAlpha(to: 0.7, duration: 0.25),
                    ])))
                }
            }
        }
        var snaps = snapshotCellLooks(coords: coords)
        let cs = cellSize()
        let fallbackSize = CGSize(width: cs.width - cellPad, height: cs.height - cellPad)
        for c in coords {
            let prior = snaps[c]
            snaps[c] = CellLook(
                texture: prior?.texture ?? representativeTexture(for: .metal),
                size: prior?.size ?? fallbackSize,
                color: fallbackColor(.metal),
                blend: 0
            )
        }
        recycleSuck(coords: coords, material: .metal, points: 800, combo: 3, snaps: snaps)
        subtleGlow(color: SKColor(red: 0.2, green: 1, blue: 0.7, alpha: 0.55))
        screenShake(strength: CGFloat(feel.shakeRecycle) * 1.4)
        onToast?("CHAIN ×3")
        // Keep a mid-bin banner flash for smoke (~1.2s).
        let banner = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        banner.text = "RECYCLE"
        banner.fontSize = 36
        banner.fontColor = SKColor(red: 0.1, green: 1, blue: 0.9, alpha: 1)
        banner.position = CGPoint(x: size.width * 0.5, y: size.height * 0.58)
        banner.zPosition = 80
        banner.setScale(0.6)
        addChild(banner)
        banner.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 1.15, duration: 0.18),
                SKAction.fadeAlpha(to: 1, duration: 0.1),
            ]),
            SKAction.wait(forDuration: 0.9),
            SKAction.fadeOut(withDuration: 0.25),
            SKAction.removeFromParent(),
        ]))
        let chain = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        chain.text = "CHAIN ×3"
        chain.fontSize = 28
        chain.fontColor = SKColor(red: 1, green: 0.3, blue: 0.85, alpha: 1)
        chain.position = CGPoint(x: size.width * 0.5, y: size.height * 0.52)
        chain.zPosition = 81
        chain.alpha = 0
        addChild(chain)
        chain.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.15),
            SKAction.fadeIn(withDuration: 0.12),
            SKAction.wait(forDuration: 1.0),
            SKAction.fadeOut(withDuration: 0.25),
            SKAction.removeFromParent(),
        ]))
    }

    private func materialGlow(_ material: Material) -> SKColor {
        switch material {
        case .metal: return SKColor(red: 0.55, green: 0.7, blue: 0.85, alpha: 0.45)
        case .plastic: return SKColor(red: 0.95, green: 0.2, blue: 0.75, alpha: 0.45)
        case .glass: return SKColor(red: 0.2, green: 0.95, blue: 1, alpha: 0.45)
        case .paper: return SKColor(red: 0.9, green: 0.7, blue: 0.35, alpha: 0.45)
        }
    }

    private func representativeTexture(for material: Material) -> SKTexture? {
        let id = JunkCatalog.all.first(where: { $0.material == material })?.id ?? .can
        return tex(JunkCatalog.textureName(for: id))
    }

    private func ghostPlateTexture(for material: Material) -> SKTexture? {
        let name: String
        switch material {
        case .metal: name = "GhostMetal"
        case .plastic: name = "GhostPlastic"
        case .glass: name = "GhostGlass"
        case .paper: name = "GhostPaper"
        }
        return tex(name)
    }

    private func chutePoint(for material: Material) -> CGPoint {
        let origin = gridOrigin()
        let cs = cellSize()
        let gridW = cs.width * CGFloat(engine.state.board.config.cols)
        let idx: CGFloat
        switch material {
        case .metal: idx = 0
        case .plastic: idx = 1
        case .glass: idx = 2
        case .paper: idx = 3
        }
        let x = origin.x + gridW + cs.width * 0.55
        let y = origin.y + cs.height * (3.5 + idx * 2.2)
        return CGPoint(x: x, y: y)
    }

    private var pipLane: Int = 0
    private func spawnScorePips(points: Int, near point: CGPoint?) {
        // Offset pips so they don't stack on each other or the chute column.
        pipLane = (pipLane + 1) % 4
        let base = point ?? CGPoint(x: size.width * 0.5, y: size.height * 0.45)
        let origin = CGPoint(
            x: min(size.width * 0.62, base.x - 24 - CGFloat(pipLane) * 18),
            y: base.y + CGFloat(pipLane) * 16
        )
        let label = SKLabelNode(fontNamed: "AvenirNext-Bold")
        label.text = "+\(points)"
        label.fontSize = 22
        label.fontColor = .white
        label.position = origin
        label.zPosition = 82
        addChild(label)
        label.run(SKAction.sequence([
            SKAction.group([
                SKAction.moveBy(x: 0, y: 48, duration: 0.55),
                SKAction.fadeOut(withDuration: 0.55),
            ]),
            SKAction.removeFromParent(),
        ]))
    }

    private func screenShake(strength: CGFloat) {
        run(SKAction.sequence([
            SKAction.moveBy(x: 0, y: -strength, duration: 0.04),
            SKAction.moveBy(x: strength * 0.4, y: strength * 1.2, duration: 0.05),
            SKAction.moveBy(x: -strength * 0.4, y: -strength * 0.6, duration: 0.05),
            SKAction.move(to: .zero, duration: 0.06),
        ]))
    }

    private func spawnParticle(named: String, at point: CGPoint, count: Int) {
        let names = [named, "SparkGold", "DebrisMetal", "DebrisNeon"]
        for i in 0..<count {
            let texName = names[i % names.count]
            let spark: SKSpriteNode
            if let t = tex(texName) {
                spark = SKSpriteNode(texture: t, size: CGSize(width: 18, height: 18))
                spark.blendMode = .alpha
            } else {
                spark = SKSpriteNode(color: SKColor(red: 1, green: 0.85, blue: 0.3, alpha: 0.9), size: CGSize(width: 6, height: 6))
            }
            spark.position = point
            spark.zPosition = 56
            spark.setScale(CGFloat.random(in: 0.5...1.1))
            addChild(spark)
            spark.run(SKAction.sequence([
                SKAction.group([
                    SKAction.moveBy(x: CGFloat.random(in: -70...70), y: CGFloat.random(in: 10...90), duration: 0.35),
                    SKAction.fadeOut(withDuration: 0.35),
                    SKAction.scale(to: 0.2, duration: 0.35),
                ]),
                SKAction.removeFromParent(),
            ]))
        }
    }

    private struct CellLook {
        var texture: SKTexture?
        var size: CGSize
        var color: SKColor
        var blend: CGFloat
    }

    private func snapshotCellLooks(coords: [BoardCoord]) -> [BoardCoord: CellLook] {
        let hid = engine.state.board.config.hiddenRows
        let vis = engine.state.board.config.visibleRows
        var out: [BoardCoord: CellLook] = [:]
        for c in coords {
            let visY = c.y - hid
            guard visY >= 0, visY < vis, let n = cellNodes[visY][c.x] else { continue }
            // Prefer junk icon texture; solid tile color lives on the parent.
            let icon = n.childNode(withName: "icon") as? SKSpriteNode
            let tex = icon?.texture ?? n.texture
            out[c] = CellLook(
                texture: tex,
                size: n.size,
                color: n.color,
                blend: tex == nil ? 1 : 0
            )
        }
        return out
    }

    private func recycleSuck(
        coords: [BoardCoord],
        material: Material = .metal,
        points: Int = 0,
        combo: Int = 1,
        snaps: [BoardCoord: CellLook] = [:]
    ) {
        let chute = chutePoint(for: material)
        let hid = engine.state.board.config.hiddenRows
        let vis = engine.state.board.config.visibleRows
        let cs = cellSize()
        for c in coords {
            let visY = c.y - hid
            guard visY >= 0, visY < vis else { continue }
            let start = positionFor(x: c.x, boardY: c.y)
            let ghostSize = snaps[c]?.size
                ?? cellNodes[visY][c.x]?.size
                ?? CGSize(width: cs.width - cellPad, height: cs.height - cellPad)
            let ghost: SKSpriteNode
            // Prefer licensed original neon ghost plates; fall back to solid+icon.
            if let plate = ghostPlateTexture(for: material) {
                ghost = SKSpriteNode(texture: plate, size: CGSize(width: ghostSize.width * 1.15, height: ghostSize.height * 1.15))
                ghost.blendMode = .alpha
                if let t = snaps[c]?.texture ?? representativeTexture(for: material) {
                    let icon = SKSpriteNode(texture: t, size: CGSize(width: ghostSize.width * 0.42, height: ghostSize.height * 0.42))
                    icon.zPosition = 1
                    icon.alpha = 0.92
                    ghost.addChild(icon)
                }
            } else if let snap = snaps[c] {
                ghost = SKSpriteNode(color: snap.color.withAlphaComponent(1), size: snap.size)
                ghost.colorBlendFactor = 1
                if let t = snap.texture {
                    let icon = SKSpriteNode(texture: t, size: CGSize(width: snap.size.width * 0.55, height: snap.size.height * 0.55))
                    icon.zPosition = 1
                    ghost.addChild(icon)
                }
            } else if let existing = cellNodes[visY][c.x] {
                ghost = SKSpriteNode(color: fallbackColor(material), size: existing.size)
                ghost.colorBlendFactor = 1
                if let iconNode = existing.childNode(withName: "icon") as? SKSpriteNode, let t = iconNode.texture {
                    let icon = SKSpriteNode(texture: t, size: CGSize(width: existing.size.width * 0.55, height: existing.size.height * 0.55))
                    icon.zPosition = 1
                    ghost.addChild(icon)
                } else if let t = representativeTexture(for: material) {
                    let icon = SKSpriteNode(texture: t, size: CGSize(width: existing.size.width * 0.55, height: existing.size.height * 0.55))
                    icon.zPosition = 1
                    ghost.addChild(icon)
                }
            } else {
                ghost = SKSpriteNode(color: fallbackColor(material), size: ghostSize)
                ghost.colorBlendFactor = 1
                if let t = representativeTexture(for: material) {
                    let icon = SKSpriteNode(texture: t, size: CGSize(width: ghostSize.width * 0.55, height: ghostSize.height * 0.55))
                    icon.zPosition = 1
                    ghost.addChild(icon)
                }
            }
            // Punch then hold readable until near the chute — fade only in the last beat.
            ghost.alpha = 1
            ghost.setScale(1.18)
            ghost.position = start
            ghost.zPosition = 57
            addChild(ghost)
            // Snappier on big chains so the bin clears with punch.
            // Keep clear juice under 300ms so the next piece spawns with no dead air.
            let dur = min(0.28, max(0.16, feel.recycleSuckSec - Double(max(0, combo - 1)) * 0.04))
            let hold = max(0.08, dur * 0.4)
            let tail = max(0.08, dur - hold)
            let suck = SKAction.sequence([
                SKAction.group([
                    SKAction.scale(to: 1.28, duration: 0.06),
                    SKAction.fadeAlpha(to: 1, duration: 0.04),
                ]),
                SKAction.group([
                    SKAction.move(to: chute, duration: dur),
                    SKAction.sequence([
                        SKAction.scale(to: 0.85, duration: hold),
                        SKAction.scale(to: 0.12, duration: tail),
                    ]),
                    SKAction.sequence([
                        SKAction.wait(forDuration: hold),
                        SKAction.fadeOut(withDuration: tail),
                    ]),
                ]),
            ])
            suck.timingMode = .easeIn
            ghost.run(SKAction.sequence([suck, SKAction.removeFromParent()]))
        }
        let particleCount = combo >= 3 ? min(60, 30 + coords.count * 3) : min(28, 10 + coords.count * 2)
        spawnParticle(named: "SparkTeal", at: chute, count: particleCount)
        if combo >= 2 {
            spawnParticle(named: "SparkMagenta", at: chute, count: particleCount / 2)
        }
        // Score pips are spawned from handleEvents near the cells — not on the chute.
        hitStop(seconds: combo >= 2 ? feel.hitStopComboSec : feel.hitStopShortSec)
    }

    private func hitStop(seconds: Double) {
        guard seconds > 0 else { return }
        // Brief speed dip — keeps SpriteKit actions alive (unlike isPaused).
        speed = 0.05
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.speed = 1
        }
    }

    private func animatePressPlate(cells: Int) {
        guard let plate = pressPlate else {
            pressJuiceFallback(cells: cells)
            return
        }
        plate.removeAllActions()
        let origin = gridOrigin()
        let cs = cellSize()
        let restY = origin.y + cs.height * CGFloat(engine.state.board.config.visibleRows) + cs.height * 1.2
        let slamY = origin.y + cs.height * 1.15
        plate.position.y = restY
        plate.setScale(1)
        let down = SKAction.moveTo(y: slamY, duration: feel.pressSlamDownSec)
        down.timingMode = .easeIn
        let squash = SKAction.sequence([
            SKAction.scaleY(to: 0.55, duration: 0.06),
            SKAction.scaleY(to: 1.05, duration: 0.08),
            SKAction.scaleY(to: 1.0, duration: 0.06),
        ])
        let up = SKAction.moveTo(y: restY, duration: feel.pressSlamUpSec)
        up.timingMode = .easeOut
        // Hold the slam pose ~1.2s so smoke/screenshots catch a readable pressed board.
        plate.run(SKAction.sequence([
            down,
            SKAction.run { [weak self] in
                guard let self else { return }
                let midX = self.size.width * 0.5
                self.screenShake(strength: CGFloat(self.feel.shakePress))
                self.hitStop(seconds: self.feel.hitStopComboSec)
                self.spawnParticle(named: "SparkMagenta", at: CGPoint(x: midX, y: slamY), count: min(20, 6 + cells))
                self.spawnParticle(named: "DebrisMetal", at: CGPoint(x: midX, y: slamY + 10), count: min(14, 4 + cells / 2))
                self.spawnParticle(named: "SparkGold", at: CGPoint(x: midX, y: slamY + 6), count: 8)
            },
            squash,
            SKAction.wait(forDuration: 1.2),
            up,
        ]))
    }

    private func pressJuiceFallback(cells: Int) {
        screenShake(strength: CGFloat(cells >= 10 ? feel.shakePress : feel.shakeRecycle))
        spawnParticle(named: "SparkMagenta", at: CGPoint(x: size.width / 2, y: gridOrigin().y + cellSize().height), count: min(20, 6 + cells))
        spawnParticle(named: "DebrisMetal", at: CGPoint(x: size.width / 2, y: gridOrigin().y + cellSize().height * 2), count: min(14, 4 + cells / 2))
    }

    private func playSnatchGrab() {
        guard !snatchBusy else { return }
        snatchBusy = true
        let paw: SKSpriteNode
        if let t = tex("RaccoonCheer") {
            paw = SKSpriteNode(texture: t, size: CGSize(width: 72, height: 72))
        } else {
            paw = SKSpriteNode(color: SKColor(red: 0.9, green: 0.7, blue: 0.4, alpha: 1), size: CGSize(width: 48, height: 28))
        }
        let origin = gridOrigin()
        let gridW = cellSize().width * CGFloat(engine.state.board.config.cols)
        paw.position = CGPoint(x: origin.x + gridW + 40, y: origin.y + cellSize().height * 6)
        paw.zPosition = 60
        paw.setScale(0.85)
        addChild(paw)
        let reach = CGPoint(x: origin.x + gridW * 0.55, y: origin.y + cellSize().height * 4)
        paw.run(SKAction.sequence([
            SKAction.group([
                SKAction.move(to: reach, duration: 0.18),
                SKAction.scale(to: 1.05, duration: 0.18),
            ]),
            SKAction.wait(forDuration: 0.08),
            SKAction.group([
                SKAction.moveBy(x: 90, y: 30, duration: 0.22),
                SKAction.fadeOut(withDuration: 0.22),
            ]),
            SKAction.run { [weak self] in self?.snatchBusy = false },
            SKAction.removeFromParent(),
        ]))
    }

    public func render(immediate: Bool = true) {
        guard didBuild else { return }
        let hid = engine.state.board.config.hiddenRows
        let vis = engine.state.board.config.visibleRows
        let cs = cellSize()
        let plateTex = tex("CellPlate")

        // Every occupied cell is a full rounded-square plate + material art on top
        // (no 2×2 merged sprites — stacking must stay cell-clear).
        for y in 0..<vis {
            for x in 0..<engine.state.board.config.cols {
                let boardY = y + hid
                let cell = engine.state.board[x, boardY]
                guard let node = cellNodes[y][x] else { continue }
                if let cell {
                    let name = JunkCatalog.textureName(for: cell.piece)
                    let cellSizePx = CGSize(width: cs.width - cellPad, height: cs.height - cellPad)
                    if let plateTex {
                        node.texture = plateTex
                    } else {
                        node.texture = nil
                    }
                    node.color = plateColor(for: cell.piece, material: cell.material)
                    node.colorBlendFactor = 1
                    node.size = cellSizePx
                    node.alpha = cell.sticky ? 0.7 : 1
                    if let icon = node.childNode(withName: "icon") as? SKSpriteNode {
                        if let t = tex(name) {
                            icon.texture = t
                            icon.color = .white
                            icon.colorBlendFactor = 0
                            icon.size = CGSize(width: cellSizePx.width * 0.62, height: cellSizePx.height * 0.62)
                            icon.alpha = 1
                        } else {
                            icon.texture = nil
                            icon.alpha = 0
                        }
                    }
                    let dest = positionFor(x: x, boardY: boardY)
                    if immediate {
                        node.removeAction(forKey: "settle")
                        node.position = dest
                        node.setScale(1)
                    } else if hypot(node.position.x - dest.x, node.position.y - dest.y) > 1 {
                        node.removeAction(forKey: "settle")
                        let drop = SKAction.move(to: dest, duration: feel.settleBounceSec)
                        drop.timingMode = .easeIn
                        let bounce = SKAction.sequence([
                            SKAction.moveBy(x: 0, y: 4, duration: 0.05),
                            SKAction.moveBy(x: 0, y: -4, duration: 0.06),
                        ])
                        node.run(SKAction.sequence([drop, bounce]), withKey: "settle")
                    }
                } else {
                    if let plateTex {
                        node.texture = plateTex
                    } else {
                        node.texture = nil
                    }
                    node.color = SKColor(white: 1, alpha: 0.04)
                    node.colorBlendFactor = 1
                    node.alpha = 1
                    node.setScale(1)
                    node.size = CGSize(width: cs.width - cellPad, height: cs.height - cellPad)
                    if let icon = node.childNode(withName: "icon") as? SKSpriteNode {
                        icon.texture = nil
                        icon.alpha = 0
                    }
                }
            }
        }
        rebuildActiveNodesIfNeeded()
        layoutActiveNodes()
        updateLandingGhost()
        updateNearMissTelegraph()
    }

    /// Pulse cells that are one junk away from a recycle so the board reads as a puzzle, not noise.
    private func updateNearMissTelegraph() {
        let almost = engine.nearMissClusters()
        let sig = almost
            .map { g in g.cells.map { "\($0.0),\($0.1)" }.sorted().joined(separator: "+") + ":\(g.material.rawValue)" }
            .sorted()
            .joined(separator: "|")
        guard sig != nearMissSignature else { return }
        nearMissSignature = sig
        enumerateChildNodes(withName: "nearMissPulse") { node, _ in
            node.removeFromParent()
        }
        guard !almost.isEmpty else { return }
        let cs = cellSize()
        for group in almost {
            let glow = materialGlow(group.material)
            for (x, y) in group.cells {
                let visY = y - engine.state.board.config.hiddenRows
                guard visY >= 0, visY < engine.state.board.config.visibleRows else { continue }
                let pulse = SKSpriteNode(
                    color: glow.withAlphaComponent(0.55),
                    size: CGSize(width: cs.width + 4, height: cs.height + 4)
                )
                pulse.name = "nearMissPulse"
                pulse.position = positionFor(x: x, boardY: y)
                pulse.zPosition = 6
                pulse.alpha = 0.35
                pulse.blendMode = .add
                addChild(pulse)
                pulse.run(SKAction.repeatForever(SKAction.sequence([
                    SKAction.fadeAlpha(to: 0.75, duration: 0.35),
                    SKAction.fadeAlpha(to: 0.28, duration: 0.35),
                ])))
            }
        }
    }

    private func rebuildActiveNodesIfNeeded() {
        guard let p = engine.state.active else {
            activeRoot?.removeFromParent()
            activeRoot = nil
            activeNodes.forEach { $0.removeFromParent() }
            activeNodes.removeAll()
            clearGhost()
            return
        }
        let tag = "\(p.id.rawValue)-\(p.rot)"
        if activeRoot?.name == tag, !activeNodes.isEmpty { return }
        activeRoot?.removeFromParent()
        activeNodes.forEach { $0.removeFromParent() }
        activeNodes.removeAll()
        let root = SKNode()
        root.name = tag
        root.zPosition = 8
        // Keep the falling piece inside the bin crop so it never draws on the frame.
        (boardCrop ?? self).addChild(root)
        activeRoot = root
        let cs = cellSize()
        let name = JunkCatalog.textureName(for: p.id)
        let plateTex = tex("CellPlate")
        // Per-cell rounded plates so every block reads as a full square (stacking stays clear).
        let shape = p.def.rotations[p.rot % p.def.rotations.count]
        for off in shape {
            let cellSizePx = CGSize(width: cs.width - cellPad, height: cs.height - cellPad)
            let n: SKSpriteNode
            if let plateTex {
                n = SKSpriteNode(texture: plateTex, size: cellSizePx)
            } else {
                n = SKSpriteNode(color: plateColor(for: p.id, material: p.def.material), size: cellSizePx)
            }
            n.color = plateColor(for: p.id, material: p.def.material)
            n.colorBlendFactor = 1
            if let t = tex(name) {
                let icon = SKSpriteNode(texture: t, size: CGSize(width: cellSizePx.width * 0.62, height: cellSizePx.height * 0.62))
                icon.name = "icon"
                icon.zPosition = 1
                n.addChild(icon)
            }
            n.position = CGPoint(x: CGFloat(off[0]) * cs.width, y: -CGFloat(off[1]) * cs.height)
            root.addChild(n)
            activeNodes.append(n)
        }
    }

    private func layoutActiveNodes() {
        guard engine.state.active != nil, let root = activeRoot else { return }
        root.position = positionForBoard(x: visualX, y: visualY)
    }

    private func positionForBoard(x: CGFloat, y: CGFloat) -> CGPoint {
        let cs = cellSize()
        let origin = gridOrigin()
        let hid = CGFloat(engine.state.board.config.hiddenRows)
        let visY = y - hid
        return CGPoint(
            x: origin.x + cs.width * (x + 0.5),
            y: origin.y + cs.height * (CGFloat(engine.state.board.config.visibleRows) - 1 - visY + 0.5)
        )
    }

    private func fallbackColor(_ mat: Material) -> SKColor {
        // Saturated solids so a near-full bin reads as ≥85% coverage, not silhouette stickers.
        switch mat {
        case .metal: return SKColor(red: 0.62, green: 0.70, blue: 0.82, alpha: 1)
        case .plastic: return SKColor(red: 0.98, green: 0.22, blue: 0.72, alpha: 1)
        case .paper: return SKColor(red: 0.95, green: 0.72, blue: 0.28, alpha: 1)
        case .glass: return SKColor(red: 0.18, green: 0.92, blue: 0.96, alpha: 1)
        }
    }

    /// Plate tint matched to each Higgsfield tile so object-shaped art still reads as a full block.
    private func plateColor(for piece: JunkID, material: Material) -> SKColor {
        switch JunkCatalog.textureName(for: piece) {
        case "can": return SKColor(red: 0.44, green: 0.43, blue: 0.60, alpha: 1)
        case "glass": return SKColor(red: 0.11, green: 0.58, blue: 0.64, alpha: 1)
        case "plastic": return SKColor(red: 0.85, green: 0.22, blue: 0.40, alpha: 1)
        case "cardboard": return SKColor(red: 0.80, green: 0.49, blue: 0.24, alpha: 1)
        case "pizza": return SKColor(red: 0.72, green: 0.55, blue: 0.41, alpha: 1)
        case "banana": return SKColor(red: 0.85, green: 0.66, blue: 0.10, alpha: 1)
        case "tire": return SKColor(red: 0.29, green: 0.25, blue: 0.40, alpha: 1)
        default: return fallbackColor(material)
        }
    }

    private func computeRaccoonMood() -> RaccoonMood {
        if engine.state.over { return .gameOver }
        if CACurrentMediaTime() < discoUntil { return .disco }
        let cfg = engine.state.board.config
        var filled = 0
        let visible = cfg.visibleRows * cfg.cols
        guard visible > 0 else { return .idle }
        for y in cfg.hiddenRows..<cfg.rows {
            for x in 0..<cfg.cols {
                if engine.state.board[x, y] != nil { filled += 1 }
            }
        }
        let fill = Double(filled) / Double(visible)
        // Panic when the bin is high — overrides a lingering cheer.
        if fill >= 0.70 { return .panic }
        if CACurrentMediaTime() < cheerUntil { return .cheer }
        if engine.state.combo >= 2 { return .cheer }
        return .idle
    }

    /// Score float beside the bin so it never covers falling junk.
    private func spawnScorePipsBesideBoard(points: Int) {
        let label = SKLabelNode(text: "+\(points)")
        label.fontName = "Menlo-Bold"
        label.fontSize = 18
        label.fontColor = SKColor(red: 0.2, green: 1, blue: 0.95, alpha: 1)
        label.horizontalAlignmentMode = .left
        let origin = gridOrigin()
        let gridW = cellSize().width * CGFloat(engine.state.board.config.cols)
        label.position = CGPoint(x: origin.x + gridW + 8, y: origin.y + cellSize().height * 4)
        label.zPosition = 90
        addChild(label)
        label.run(SKAction.sequence([
            SKAction.group([
                SKAction.moveBy(x: 0, y: 36, duration: 0.55),
                SKAction.fadeOut(withDuration: 0.55),
            ]),
            SKAction.removeFromParent(),
        ]))
    }

    /// 2-frame slam burst; art has padding so we scale up to ~piece width.
    private func presentSlamBurst(at point: CGPoint, pieceWidth: CGFloat) {
        let frames = ["Slam01", "Slam02"].compactMap { tex($0) }
        guard !frames.isEmpty else { return }
        let node = SKSpriteNode(texture: frames[0])
        let target = max(pieceWidth * 1.15, cellSize().width * 2.6)
        let base = max(frames[0].size().width, 1)
        // Extra padding in the PNG — overscale so the burst fills the piece width.
        let scale = (target / base) * 1.55
        node.size = CGSize(width: frames[0].size().width * scale, height: frames[0].size().height * scale)
        node.position = point
        node.zPosition = 70
        node.blendMode = .add
        addChild(node)
        var actions: [SKAction] = []
        for (i, frame) in frames.enumerated() {
            actions.append(SKAction.run {
                node.texture = frame
                node.size = CGSize(width: frame.size().width * scale, height: frame.size().height * scale)
            })
            actions.append(SKAction.wait(forDuration: i == 0 ? 0.05 : 0.09))
        }
        actions.append(SKAction.group([
            SKAction.fadeOut(withDuration: 0.12),
            SKAction.scale(by: 1.12, duration: 0.12),
        ]))
        actions.append(SKAction.removeFromParent())
        node.run(SKAction.sequence(actions))
    }

    /// Sparkle strip across the rows that just recycled.
    private func presentClearBurst(across coords: [BoardCoord]) {
        guard let burst = tex("ClearBurst"), !coords.isEmpty else { return }
        let ys = Set(coords.map(\.y))
        let cs = cellSize()
        let origin = gridOrigin()
        let gridW = cs.width * CGFloat(engine.state.board.config.cols)
        for boardY in ys {
            let node = SKSpriteNode(texture: burst)
            let rowY = positionFor(x: 0, boardY: boardY).y
            node.size = CGSize(width: gridW * 1.08, height: max(cs.height * 1.35, gridW * 0.22))
            node.position = CGPoint(x: origin.x + gridW / 2, y: rowY)
            node.zPosition = 68
            node.alpha = 0.95
            node.blendMode = .add
            addChild(node)
            node.run(SKAction.sequence([
                SKAction.group([
                    SKAction.fadeOut(withDuration: 0.35),
                    SKAction.scaleY(to: 1.25, duration: 0.35),
                ]),
                SKAction.removeFromParent(),
            ]))
        }
    }

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        touchStart = t.location(in: self)
        touchStartTime = CACurrentMediaTime()
        movedCols = 0
        dragAccumX = 0
        softDragging = false
    }

    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first, let start = touchStart, engine.state.active != nil else { return }
        let p = t.location(in: self)
        let dx = p.x - start.x
        let dy = p.y - start.y
        let colW = max(1, cellSize().width)
        // 1:1 finger → column with ease snap (not a hard teleport).
        let cols = Int((dx / colW).rounded())
        if cols != movedCols {
            let step = cols > movedCols ? 1 : -1
            var target = movedCols
            var nudged = false
            while target != cols {
                target += step
                if noteLockResetMove({ engine.tryMove(dx: step, dy: 0) }) { nudged = true }
                else { break }
            }
            movedCols = target
            if nudged {
                // Ease toward discrete cell — smoothActivePose does the rest.
                onPieceSnap?()
            }
            render(immediate: false)
        }
        // Slow drag down = soft drop; never latches past touch end/cancel.
        if dy < -cellSize().height * 0.55, abs(dy) > abs(dx) * 0.6 {
            softDragging = true
        } else if abs(dx) > abs(dy) {
            softDragging = false
        }
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        defer { clearTouchState() }
        guard let t = touches.first, let start = touchStart else { return }
        let p = t.location(in: self)
        let dx = p.x - start.x
        let dy = p.y - start.y
        let elapsed = CACurrentMediaTime() - touchStartTime
        let dist = hypot(dx, dy)
        let origin = gridOrigin()
        let midX = origin.x + cellSize().width * CGFloat(engine.state.board.config.cols) * 0.5

        // Tap: left half CCW, right half CW.
        if dist < 32, elapsed < 0.35 {
            let clockwise = start.x >= midX
            if noteLockResetMove({ engine.tryRotate(clockwise: clockwise) }) {
                rebuildActiveNodesIfNeeded()
                snapActivePose()
                onPieceSnap?()
            }
            render(immediate: false)
            return
        }
        // Fast swipe down = hard drop.
        if dy < -48, abs(dy) > abs(dx) * 0.7, elapsed < 0.35 {
            softDragging = false
            engine.hardDrop()
            groundedElapsed = 0
            lockResets = 0
            handleEvents()
            hasVisualPose = false
            render(immediate: false)
            if engine.state.over { onGameOver?(engine.state) }
            return
        }
        // Swipe up = HOLD.
        if dy > 52, abs(dy) > abs(dx) {
            engine.stash()
            groundedElapsed = 0
            lockResets = 0
            hasVisualPose = false
            render(immediate: true)
        }
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Lost touch must never latch soft-drop or block locking.
        clearTouchState()
    }

    public func moveLeft() {
        if noteLockResetMove({ engine.tryMove(dx: -1, dy: 0) }) {
            snapActivePose()
            onPieceSnap?()
        }
        render(immediate: false)
    }
    public func moveRight() {
        if noteLockResetMove({ engine.tryMove(dx: 1, dy: 0) }) {
            snapActivePose()
            onPieceSnap?()
        }
        render(immediate: false)
    }
    public func rotate() {
        if noteLockResetMove({ engine.tryRotate(clockwise: true) }) {
            rebuildActiveNodesIfNeeded()
            snapActivePose()
            onPieceSnap?()
        }
        render(immediate: false)
    }
    public func soft() {
        // One soft step only — never a latched repeat from a lost touch.
        _ = engine.softDrop()
        render(immediate: false)
    }
    public func hard() {
        softDragging = false
        clearTouchState()
        engine.hardDrop()
        groundedElapsed = 0
        lockResets = 0
        handleEvents()
        hasVisualPose = false
        render(immediate: false)
        if engine.state.over { onGameOver?(engine.state) }
    }
    public func stash() { engine.stash(); hasVisualPose = false; render(immediate: true) }
    public func magnet() {
        // Legacy hook → Snatch random for HUD button compat during transition.
        guard engine.state.snatchAvailable else { return }
        playSnatchGrab()
        _ = engine.snatchRandom()
        handleEvents()
        render(immediate: false)
    }
    public func slamPress() {
        _ = engine.slamPress()
        handleEvents()
        render(immediate: false)
    }
    public func revive() {
        engine.revive()
        raccoonMood = .idle
        hasVisualPose = false
        render(immediate: true)
    }
}
#else
import Foundation
#endif
