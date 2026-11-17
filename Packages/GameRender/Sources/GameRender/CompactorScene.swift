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
    public var autoplay = false
    /// Demo-only elapsed time for scripted near-miss → game-over beats.
    private var autoplayElapsed: TimeInterval = 0
    private var demoPhase: Int = 0
    public var preferredFPS: Int = 60
    public private(set) var measuredFPS: Double = 60
    public var raccoonMood: RaccoonMood = .idle
    public var feel: FeelConfig = ConfigLoader.feelOrFallback()

    public enum RaccoonMood: Equatable { case idle, cheer, panic }

    private var cellNodes: [[SKSpriteNode?]] = []
    private var activeNodes: [SKSpriteNode] = []
    private var activeRoot: SKNode?
    private var fpsLabel: SKLabelNode?
    private var alleyNode: SKSpriteNode?
    private var pressPlate: SKSpriteNode?
    private var gravityAcc: TimeInterval = 0
    private var lockAcc: TimeInterval = 0
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

    private var touchStart: CGPoint?
    private var touchStartTime: TimeInterval = 0
    private var movedCols: Int = 0

    /// Small toast text for SwiftUI banner (not big mid-board labels).
    public var onToast: ((String) -> Void)?
    /// Fired once after the first real board paint (dark fill + cells — never blank gray).
    /// May be assigned after `didMove`; fires immediately if the board is already ready.
    public var onFirstGameFrame: (() -> Void)? {
        didSet { noteFirstGameFrame() }
    }
    private var didFireFirstGameFrame = false

    public override func didMove(to view: SKView) {
        let charcoal = SKColor(red: 0.05, green: 0.06, blue: 0.10, alpha: 1)
        backgroundColor = charcoal
        view.backgroundColor = charcoal
        preferredFPS = 60
        view.preferredFramesPerSecond = preferredFPS
        view.ignoresSiblingOrder = true
        view.isMultipleTouchEnabled = false
        // Decode critical textures before first paint so the bin never flashes flat gray.
        for name in Self.requiredJunkTextureNames + ["AlleyBackground", "DumpsterFrame"] {
            _ = tex(name)
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
        lockAcc = 0
        raccoonMood = .idle
        render(immediate: true)
    }

    public func applyShot(_ shot: String) {
        pendingShot = shot
        engine.applyShotScenario(shot)
        gravityAcc = 0
        lockAcc = 0
        if shot == "recycle" { raccoonMood = .cheer }
        else if shot == "compactor" || shot == "press" { raccoonMood = .cheer }
        else if shot == "revive" || shot == "game-over" { raccoonMood = .panic }
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
            SKAction.wait(forDuration: 16),
            SKAction.run { [weak self] in
                guard let self, !self.engine.state.over else { return }
                self.engine.fillPressMeter()
                _ = self.engine.slamPress()
                self.handleEvents()
                self.render(immediate: false)
            },
            SKAction.wait(forDuration: 8),
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
            frame.size = CGSize(width: gridW + cs.width * 0.9, height: gridH + cs.height * 1.1)
            frame.position = CGPoint(x: origin.x + gridW / 2, y: origin.y + gridH / 2 - cs.height * 0.05)
            frame.zPosition = 0
            addChild(frame)
        } else {
            let frame = SKShapeNode(rectOf: CGSize(width: gridW + 12, height: gridH + 12), cornerRadius: 10)
            frame.strokeColor = SKColor(red: 0, green: 0.95, blue: 1, alpha: 0.75)
            frame.fillColor = SKColor(red: 0.04, green: 0.05, blue: 0.09, alpha: 0.55)
            frame.lineWidth = 3
            frame.position = CGPoint(x: origin.x + gridW / 2, y: origin.y + gridH / 2)
            addChild(frame)
        }

        for side in [-1, 1] {
            let rail = SKSpriteNode(
                color: SKColor(red: 0.95, green: 0.2, blue: 0.75, alpha: 0.65),
                size: CGSize(width: max(5, cs.width * 0.12), height: gridH)
            )
            rail.position = CGPoint(
                x: origin.x + gridW / 2 + CGFloat(side) * (gridW / 2 + cs.width * 0.28),
                y: origin.y + gridH / 2
            )
            rail.zPosition = 2
            addChild(rail)
        }

        // Crop cells to the bin's inner rectangle so pieces never draw on the frame.
        let crop = SKCropNode()
        crop.zPosition = 3
        let mask = SKSpriteNode(
            color: .white,
            size: CGSize(width: gridW - 2, height: gridH - 2)
        )
        mask.position = CGPoint(x: origin.x + gridW / 2, y: origin.y + gridH / 2)
        crop.maskNode = mask
        addChild(crop)

        // Dark board backdrop — never flat gray while textures load.
        let boardFill = SKSpriteNode(
            color: SKColor(red: 0.05, green: 0.06, blue: 0.10, alpha: 1),
            size: CGSize(width: gridW - 2, height: gridH - 2)
        )
        boardFill.position = CGPoint(x: origin.x + gridW / 2, y: origin.y + gridH / 2)
        boardFill.zPosition = 0
        crop.addChild(boardFill)

        for y in 0..<vis {
            for x in 0..<cols {
                // Parent = solid material tile; child icon overlays at ≤60% of cell.
                let n = SKSpriteNode(
                    color: SKColor(white: 1, alpha: 0.04),
                    size: CGSize(width: cs.width - cellPad, height: cs.height - cellPad)
                )
                n.position = positionFor(x: x, boardY: y + engine.state.board.config.hiddenRows)
                n.zPosition = 1
                n.name = "cell"
                let icon = SKSpriteNode(color: .clear, size: CGSize(width: (cs.width - cellPad) * 0.55, height: (cs.height - cellPad) * 0.55))
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
        let rows = CGFloat(engine.state.board.config.visibleRows)
        let byWidth = size.width * 0.85 / cols
        let byHeight = size.height * 0.92 / rows
        let s = min(byWidth, byHeight)
        return CGSize(width: s, height: s)
    }

    private func gridOrigin() -> CGPoint {
        let cs = cellSize()
        let cols = CGFloat(engine.state.board.config.cols)
        let rows = CGFloat(engine.state.board.config.visibleRows)
        let totalW = cs.width * cols
        let totalH = cs.height * rows
        return CGPoint(
            x: (size.width - totalW) / 2,
            y: (size.height - totalH) / 2 - size.height * 0.02
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

        let filledTop = (0..<engine.state.board.config.cols).contains { x in
            engine.state.board[x, engine.state.board.config.hiddenRows] != nil
        }
        let nextMood: RaccoonMood
        if engine.state.over || filledTop { nextMood = .panic }
        else if engine.state.combo >= 2 { nextMood = .cheer }
        else { nextMood = .idle }
        if nextMood != raccoonMood { raccoonMood = nextMood }

        // Continuous visual smoothing toward discrete logic pose.
        smoothActivePose(dt: dt)

        if autoplay {
            autoplayElapsed += TimeInterval(dt)
            // Live-run tension only — never applyShotScenario mid-demo (that rolled level/score backwards).
            if demoPhase == 0, engine.isNearOverflow(threshold: feel.nearMissRows) {
                demoPhase = 1
                onToast?("SO CLOSE")
                raccoonMood = .panic
            }
            gravityAcc += Double(dt)
            if gravityAcc > 0.28 {
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
        let grav = max(feel.gravityMinSec, feel.gravityBaseSec - Double(engine.state.level) * feel.gravityLevelStep)
        gravityAcc += Double(dt)
        if gravityAcc >= grav {
            gravityAcc = 0
            if !engine.softDrop() {
                lockAcc += grav
                if lockAcc > feel.lockDelaySec {
                    lockAcc = 0
                    engine.lock()
                    handleEvents()
                    if engine.state.over { onGameOver?(engine.state) }
                }
            } else {
                lockAcc = 0
            }
            render(immediate: false)
        }
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
            case .locked:
                hasVisualPose = false
            case .recycled(_, let cells, let score, _, let material, let coords):
                // Snapshot textures BEFORE render clears the cells (real item ghosts, not flat squares).
                // If lock→recycle happened before a paint, synthesize solid+icon from material.
                var snaps = snapshotCellLooks(coords: coords)
                let cs = cellSize()
                let fallbackSize = CGSize(width: cs.width - cellPad, height: cs.height - cellPad)
                for c in coords {
                    let prior = snaps[c]
                    let hasIcon = prior?.texture != nil
                    let solid = fallbackColor(material)
                    snaps[c] = CellLook(
                        texture: prior?.texture ?? representativeTexture(for: material),
                        size: prior?.size ?? fallbackSize,
                        color: solid,
                        blend: hasIcon ? 0 : 0
                    )
                }
                recycleSuck(coords: coords, material: material, points: score, combo: engine.state.combo, snaps: snaps)
                subtleGlow(color: materialGlow(material))
                screenShake(strength: CGFloat(feel.shakeRecycle) * (engine.state.combo >= 2 ? 1.35 : 1.0))
                if engine.state.combo >= 2 {
                    onToast?("CHAIN ×\(engine.state.combo)")
                    raccoonMood = .cheer
                } else {
                    onToast?("RECYCLE")
                }
                spawnScorePips(points: score, near: coords.first.map { positionFor(x: $0.x, boardY: $0.y) })
                _ = cells
            case .pressed(let cells, _, _):
                animatePressPlate(cells: cells)
                raccoonMood = .cheer
                onToast?("Press slam")
            case .orderCompleted(let order):
                onToast?("Order done · \(order.label)")
            case .snatchUsed:
                playSnatchGrab()
                onToast?("Snatch!")
            case .leveledUp(let lvl):
                onToast?("Level \(lvl)")
            case .spawned:
                hasVisualPose = false
            case .gameOver:
                raccoonMood = .panic
            default: break
            }
        }
        onEvents?(ev)
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
        recycleSuck(coords: coords, material: .metal, points: 800, combo: 3)
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
            let ghost: SKSpriteNode
            // Always build a solid material tile ghost; overlay icon when we have a snapshot.
            if let snap = snaps[c] {
                ghost = SKSpriteNode(color: snap.color, size: snap.size)
                ghost.colorBlendFactor = 1
                if let t = snap.texture {
                    let icon = SKSpriteNode(texture: t, size: CGSize(width: snap.size.width * 0.58, height: snap.size.height * 0.58))
                    icon.zPosition = 1
                    ghost.addChild(icon)
                }
            } else if let existing = cellNodes[visY][c.x] {
                ghost = SKSpriteNode(color: existing.color.withAlphaComponent(1), size: existing.size)
                ghost.colorBlendFactor = 1
                if let iconNode = existing.childNode(withName: "icon") as? SKSpriteNode, let t = iconNode.texture {
                    let icon = SKSpriteNode(texture: t, size: CGSize(width: existing.size.width * 0.58, height: existing.size.height * 0.58))
                    icon.zPosition = 1
                    ghost.addChild(icon)
                }
            } else {
                ghost = SKSpriteNode(color: fallbackColor(material), size: CGSize(width: cs.width - cellPad, height: cs.height - cellPad))
            }
            ghost.position = start
            ghost.zPosition = 57
            addChild(ghost)
            let dur = feel.recycleSuckSec
            let suck = SKAction.group([
                SKAction.move(to: chute, duration: dur),
                SKAction.scale(to: 0.12, duration: dur),
                SKAction.fadeOut(withDuration: dur),
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
        // Hide per-cell tiles that belong to a unified 2×2 object (crate / tire).
        var covered = Set<BoardCoord>()
        for y in 0..<vis {
            for x in 0..<engine.state.board.config.cols {
                let by = y + hid
                guard let cell = engine.state.board[x, by], JunkCatalog.def(for: cell.piece).isSquare else { continue }
                guard x + 1 < engine.state.board.config.cols, by + 1 < engine.state.board.config.rows else { continue }
                // Anchor at top-left of a 2×2 footprint when all four match.
                if engine.state.board[x + 1, by]?.piece == cell.piece,
                   engine.state.board[x, by + 1]?.piece == cell.piece,
                   engine.state.board[x + 1, by + 1]?.piece == cell.piece {
                    covered.insert(BoardCoord(x + 1, by))
                    covered.insert(BoardCoord(x, by + 1))
                    covered.insert(BoardCoord(x + 1, by + 1))
                }
            }
        }

        for y in 0..<vis {
            for x in 0..<engine.state.board.config.cols {
                let boardY = y + hid
                let cell = engine.state.board[x, boardY]
                guard let node = cellNodes[y][x] else { continue }
                if covered.contains(BoardCoord(x, boardY)) {
                    node.alpha = 0
                    continue
                }
                if let cell {
                    let name = JunkCatalog.textureName(for: cell.piece)
                    let square = JunkCatalog.def(for: cell.piece).isSquare
                    // Only the 2×2 *anchor* cell (top-left of a complete footprint) draws at 2×2.
                    // Partial remnants after recycle/press always fall back to a filled 1×1 cell.
                    let isSquareAnchor = square
                        && !covered.contains(BoardCoord(x, boardY))
                        && x + 1 < engine.state.board.config.cols
                        && boardY + 1 < engine.state.board.config.rows
                        && engine.state.board[x + 1, boardY]?.piece == cell.piece
                        && engine.state.board[x, boardY + 1]?.piece == cell.piece
                        && engine.state.board[x + 1, boardY + 1]?.piece == cell.piece
                    let span: CGFloat = isSquareAnchor ? 2 : 1
                    let cellSizePx = CGSize(width: cs.width * span - cellPad, height: cs.height * span - cellPad)
                    // Solid opaque material tile (rounded via texture-less sprite) + junk icon on top ≤60%.
                    // colorBlendFactor alone cannot fill transparent silhouette pixels.
                    node.texture = nil
                    node.color = fallbackColor(cell.material)
                    node.colorBlendFactor = 1
                    node.size = cellSizePx
                    node.alpha = cell.sticky ? 0.7 : 1
                    if let icon = node.childNode(withName: "icon") as? SKSpriteNode {
                        if let t = tex(name) {
                            icon.texture = t
                            icon.color = .white
                            icon.colorBlendFactor = 0
                            let iconScale: CGFloat = isSquareAnchor ? 0.50 : 0.58
                            icon.size = CGSize(width: cellSizePx.width * iconScale, height: cellSizePx.height * iconScale)
                            icon.alpha = 1
                        } else {
                            icon.texture = nil
                            icon.alpha = 0
                        }
                    }
                    let dest: CGPoint
                    if isSquareAnchor {
                        dest = CGPoint(
                            x: positionFor(x: x, boardY: boardY).x + cs.width * 0.5,
                            y: positionFor(x: x, boardY: boardY).y - cs.height * 0.5
                        )
                    } else {
                        dest = positionFor(x: x, boardY: boardY)
                    }
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
                    node.texture = nil
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
    }

    private func rebuildActiveNodesIfNeeded() {
        guard let p = engine.state.active else {
            activeRoot?.removeFromParent()
            activeRoot = nil
            activeNodes.forEach { $0.removeFromParent() }
            activeNodes.removeAll()
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
        addChild(root)
        activeRoot = root
        let cs = cellSize()
        let name = JunkCatalog.textureName(for: p.id)
        // Per-cell segments so the art matches the collision footprint in every rotation.
        // Square items (crate/tire) stay one 2×2 sprite; everything else is one filled cell per offset.
        if p.def.isSquare {
            let cellSizePx = CGSize(width: cs.width * 2 - cellPad, height: cs.height * 2 - cellPad)
            let n = SKSpriteNode(color: fallbackColor(p.def.material), size: cellSizePx)
            n.colorBlendFactor = 1
            if let t = tex(name) {
                let icon = SKSpriteNode(texture: t, size: CGSize(width: cellSizePx.width * 0.50, height: cellSizePx.height * 0.50))
                icon.name = "icon"
                icon.zPosition = 1
                n.addChild(icon)
            }
            n.position = CGPoint(x: cs.width * 0.5, y: -cs.height * 0.5)
            root.addChild(n)
            activeNodes.append(n)
        } else {
            let shape = p.def.rotations[p.rot % p.def.rotations.count]
            for off in shape {
                let cellSizePx = CGSize(width: cs.width - cellPad, height: cs.height - cellPad)
                let n = SKSpriteNode(color: fallbackColor(p.def.material), size: cellSizePx)
                n.colorBlendFactor = 1
                if let t = tex(name) {
                    let icon = SKSpriteNode(texture: t, size: CGSize(width: cellSizePx.width * 0.58, height: cellSizePx.height * 0.58))
                    icon.name = "icon"
                    icon.zPosition = 1
                    n.addChild(icon)
                }
                n.position = CGPoint(x: CGFloat(off[0]) * cs.width, y: -CGFloat(off[1]) * cs.height)
                root.addChild(n)
                activeNodes.append(n)
            }
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
        switch mat {
        case .metal: return SKColor(red: 0.55, green: 0.62, blue: 0.72, alpha: 1)
        case .plastic: return SKColor(red: 0.95, green: 0.2, blue: 0.75, alpha: 1)
        case .paper: return SKColor(red: 0.85, green: 0.7, blue: 0.35, alpha: 1)
        case .glass: return SKColor(red: 0.2, green: 0.9, blue: 0.95, alpha: 1)
        }
    }

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        touchStart = t.location(in: self)
        touchStartTime = CACurrentMediaTime()
        movedCols = 0
    }

    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first, let start = touchStart, engine.state.active != nil else { return }
        let p = t.location(in: self)
        let dx = p.x - start.x
        let colW = max(1, cellSize().width)
        let cols = Int((dx / colW).rounded())
        if cols != movedCols {
            let step = cols > movedCols ? 1 : -1
            var target = movedCols
            while target != cols {
                target += step
                _ = engine.tryMove(dx: step, dy: 0)
            }
            movedCols = cols
            render(immediate: false)
        }
        let dy = p.y - start.y
        if dy < -cellSize().height * 0.8 {
            _ = engine.softDrop()
            render(immediate: false)
        }
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first, let start = touchStart else { return }
        let p = t.location(in: self)
        let dx = p.x - start.x
        let dy = p.y - start.y
        let dt = CACurrentMediaTime() - touchStartTime
        let dist = hypot(dx, dy)

        // Forgiving: small tap = rotate; clear downward flick = drop; upward = hold.
        if dist < 28, dt < 0.4 {
            _ = engine.tryRotate()
            render(immediate: false)
        } else if dy < -40, abs(dy) > abs(dx) * 0.7 {
            engine.hardDrop()
            handleEvents()
            hasVisualPose = false
            render(immediate: false)
            if engine.state.over { onGameOver?(engine.state) }
        } else if dy > 50, abs(dy) > abs(dx) {
            engine.stash()
            hasVisualPose = false
            render(immediate: true)
        }
        touchStart = nil
    }

    public func moveLeft() { _ = engine.tryMove(dx: -1, dy: 0); render(immediate: false) }
    public func moveRight() { _ = engine.tryMove(dx: 1, dy: 0); render(immediate: false) }
    public func rotate() { _ = engine.tryRotate(); rebuildActiveNodesIfNeeded(); render(immediate: false) }
    public func soft() { _ = engine.softDrop(); render(immediate: false) }
    public func hard() {
        engine.hardDrop()
        handleEvents()
        hasVisualPose = false
        render(immediate: false)
        if engine.state.over { onGameOver?(engine.state) }
    }
    public func stash() { engine.stash(); hasVisualPose = false; render(immediate: true) }
    public func magnet() {
        // Legacy hook → Snatch random for HUD button compat during transition.
        guard engine.state.snatchAvailable else { return }
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
