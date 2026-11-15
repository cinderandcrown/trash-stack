// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

#if canImport(SpriteKit)
import SpriteKit
import UIKit
import QuartzCore
import GameCore

/// SpriteKit playfield — atlas textures + baked colors. No per-node glow/shader spam (jetsam-safe).
public final class CompactorScene: SKScene {
    public var engine = GameEngine(seed: UInt64.random(in: 1...UInt64.max))
    public var onGameOver: ((GameState) -> Void)?
    public var onEvents: (([GameEvent]) -> Void)?
    public var autoplay = false
    public var preferredFPS: Int = 60
    public private(set) var measuredFPS: Double = 60
    /// Mirrored to the SwiftUI HUD raccoon portrait.
    public var raccoonMood: RaccoonMood = .idle

    public enum RaccoonMood: Equatable { case idle, cheer, panic }

    private var cellNodes: [[SKSpriteNode?]] = []
    private var activeNodes: [SKSpriteNode] = []
    private var comboLabel: SKLabelNode?
    private var fpsLabel: SKLabelNode?
    private var alleyNode: SKSpriteNode?
    private var gravityAcc: TimeInterval = 0
    private var lockAcc: TimeInterval = 0
    private var lastTime: TimeInterval = 0
    private var fpsSamples: [Double] = []
    private var didBuild = false
    /// Near-zero pad so junk art fills each cell edge-to-edge.
    private let cellPad: CGFloat = 0.5
    /// Evidence shots hold juice on-screen longer for screenshots.
    private var holdPresentation = false
    private var pendingShot: String?
    private var demoOnGameOver: (() -> Void)?
    private var demoPhase: Int = 0

    // Gestures
    private var touchStart: CGPoint?
    private var touchStartTime: TimeInterval = 0
    private var movedCols: Int = 0

    public override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.03, green: 0.03, blue: 0.07, alpha: 1)
        preferredFPS = 60
        view.preferredFramesPerSecond = preferredFPS
        view.ignoresSiblingOrder = true
        view.isMultipleTouchEnabled = false
        rebuild()
    }

    public override func didChangeSize(_ oldSize: CGSize) {
        // SpriteView resizeFill — rebuild once we have a real size.
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
        render()
    }

    public func applyShot(_ shot: String) {
        pendingShot = shot
        engine.applyShotScenario(shot)
        gravityAcc = 0
        lockAcc = 0
        holdPresentation = ["compactor", "recycle", "game", "gameplay"].contains(shot)
        if shot == "recycle" { raccoonMood = .cheer }
        else if shot == "compactor" { raccoonMood = .cheer }
        else if shot == "revive" || shot == "game-over" { raccoonMood = .panic }
        else { raccoonMood = .idle }
        if didBuild {
            render()
            presentPendingShotJuice()
        }
    }

    /// Choreographed demo for App Store gameplay video: stack → Big Crush → recycle → game over.
    public func startDemoChoreography(onGameOverBeat: @escaping () -> Void) {
        demoOnGameOver = onGameOverBeat
        demoPhase = 0
        autoplay = true
        removeAction(forKey: "demoChoreography")
        let crushAt = SKAction.run { [weak self] in
            guard let self else { return }
            self.demoPhase = 1
            self.autoplay = false
            self.engine.applyShotScenario("compactor")
            self.render()
            self.presentCrushMoment(rowCount: 3)
        }
        let resumeAfterCrush = SKAction.run { [weak self] in
            guard let self else { return }
            self.holdPresentation = false
            self.autoplay = true
            // Leave a playable mid-stack after the crush showcase.
            self.engine.applyShotScenario("demo")
            self.render()
        }
        let recycleAt = SKAction.run { [weak self] in
            guard let self else { return }
            self.demoPhase = 2
            self.autoplay = false
            self.engine.applyShotScenario("recycle")
            self.render()
            self.presentRecycleMoment()
            // Actually resolve a recycle after the banner holds.
            self.run(SKAction.sequence([
                SKAction.wait(forDuration: 1.4),
                SKAction.run { [weak self] in
                    guard let self else { return }
                    self.holdPresentation = false
                    self.engine.hardDrop()
                    self.handleEvents()
                    self.render()
                    self.autoplay = true
                },
            ]))
        }
        let topOut = SKAction.run { [weak self] in
            guard let self else { return }
            self.demoPhase = 3
            self.autoplay = false
            self.engine.applyShotScenario("revive")
            self.render()
            self.raccoonMood = .panic
            self.demoOnGameOver?()
        }
        run(SKAction.sequence([
            SKAction.wait(forDuration: 10),
            crushAt,
            SKAction.wait(forDuration: 3.5),
            resumeAfterCrush,
            SKAction.wait(forDuration: 8),
            recycleAt,
            SKAction.wait(forDuration: 6),
            topOut,
        ]), withKey: "demoChoreography")
    }

    private func presentPendingShotJuice() {
        guard let shot = pendingShot else { return }
        if shot == "compactor" {
            presentCrushMoment(rowCount: 3)
        } else if shot == "recycle" {
            presentRecycleMoment()
        }
    }

    private func tex(_ name: String) -> SKTexture? {
        // Never call SKTexture(imageNamed:) alone — miss → red-X placeholder.
        JunkTextureLoader.texture(named: name)
    }

    /// Names every board piece must resolve from the app asset catalog (no red-X).
    /// `nonisolated` so unit tests can read this without MainActor (SKScene is isolated).
    nonisolated public static var requiredJunkTextureNames: [String] {
        JunkID.allCases.map(\.rawValue)
    }

    private func rebuild() {
        removeAllChildren()
        cellNodes = []
        activeNodes = []
        alleyNode = nil
        comboLabel = nil
        fpsLabel = nil
        didBuild = false
        guard size.width > 10, size.height > 10 else { return }

        // Full-bleed rainy neon alley behind the compactor (dimmed).
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
            // Frame hugs the well with a modest chrome margin — fills most of the safe play area.
            frame.size = CGSize(width: gridW + cs.width * 0.9, height: gridH + cs.height * 1.1)
            frame.position = CGPoint(x: origin.x + gridW / 2, y: origin.y + gridH / 2 - cs.height * 0.05)
            frame.zPosition = 0
            addChild(frame)
        } else {
            let frame = SKShapeNode(
                rectOf: CGSize(width: gridW + 12, height: gridH + 12),
                cornerRadius: 10
            )
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

        for y in 0..<vis {
            for x in 0..<cols {
                let n = SKSpriteNode(
                    color: SKColor(white: 1, alpha: 0.05),
                    size: CGSize(width: cs.width - cellPad, height: cs.height - cellPad)
                )
                n.position = positionFor(x: x, boardY: y + engine.state.board.config.hiddenRows)
                n.zPosition = 3
                addChild(n)
                cellNodes[y][x] = n
            }
        }

        // Parallax rain streaks over the alley.
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

        // Subtle alley drift for parallax.
        if let alleyNode {
            alleyNode.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.moveBy(x: 8, y: 4, duration: 4.5),
                SKAction.moveBy(x: -8, y: -4, duration: 4.5),
            ])))
        }

        let combo = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        combo.fontSize = 26
        combo.fontColor = SKColor(red: 0, green: 1, blue: 0.95, alpha: 1)
        combo.position = CGPoint(x: size.width / 2, y: size.height * 0.82)
        combo.zPosition = 45
        combo.alpha = 0
        addChild(combo)
        comboLabel = combo

        // FPS is opt-in only (`-showFPS`). Never on release or smoke/screenshot builds.
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
        render()
        presentPendingShotJuice()
    }

    private func cellSize() -> CGSize {
        let cols = CGFloat(engine.state.board.config.cols)
        let rows = CGFloat(engine.state.board.config.visibleRows)
        // Target ~85% screen width; only shrink if the well would overflow the scene height.
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
        // Center horizontally; sit slightly low so HUD chrome above stays clear.
        return CGPoint(
            x: (size.width - totalW) / 2,
            y: (size.height - totalH) / 2 - size.height * 0.02
        )
    }

    private func positionFor(x: Int, boardY: Int) -> CGPoint {
        let cs = cellSize()
        let origin = gridOrigin()
        let hid = engine.state.board.config.hiddenRows
        let visY = boardY - hid
        return CGPoint(
            x: origin.x + cs.width * (CGFloat(x) + 0.5),
            y: origin.y + cs.height * (CGFloat(engine.state.board.config.visibleRows - 1 - visY) + 0.5)
        )
    }

    public override func update(_ currentTime: TimeInterval) {
        if lastTime > 0 {
            let dt = currentTime - lastTime
            if dt > 0, dt < 1 {
                let fps = min(144, 1.0 / dt)
                fpsSamples.append(fps)
                if fpsSamples.count > 30 { fpsSamples.removeFirst() }
                measuredFPS = fpsSamples.reduce(0, +) / Double(fpsSamples.count)
                fpsLabel?.text = String(format: "%.0f fps", measuredFPS)
            }
        }
        lastTime = currentTime

        let filledTop = (0..<engine.state.board.config.cols).contains { x in
            engine.state.board[x, engine.state.board.config.hiddenRows + 2] != nil
        }
        let nextMood: RaccoonMood
        if engine.state.over || filledTop { nextMood = .panic }
        else if engine.state.combo >= 2 { nextMood = .cheer }
        else { nextMood = .idle }
        if nextMood != raccoonMood { raccoonMood = nextMood }

        if autoplay {
            gravityAcc += 1 / 60
            if gravityAcc > 0.14 {
                gravityAcc = 0
                engine.autoplayStep()
                handleEvents()
                if engine.state.over { onGameOver?(engine.state) }
                render()
            }
            return
        }
        guard !engine.state.over, engine.state.active != nil else { return }
        let grav = max(0.08, 0.55 - Double(engine.state.level) * 0.03)
        gravityAcc += 1.0 / 60.0
        if gravityAcc >= grav {
            gravityAcc = 0
            if !engine.softDrop() {
                lockAcc += grav
                if lockAcc > 0.45 {
                    lockAcc = 0
                    engine.lock()
                    handleEvents()
                    if engine.state.over { onGameOver?(engine.state) }
                }
            } else {
                lockAcc = 0
            }
            render()
        }
    }

    private func handleEvents() {
        let ev = engine.drainEvents()
        for e in ev {
            switch e {
            case .locked:
                break
            case .cleared(let rows, _, _):
                crushJuice(rows: rows)
                showCombo()
                if rows.count >= 3 {
                    raccoonMood = .cheer
                    bigCrushBanner(multiplier: rows.count)
                }
            case .recycled:
                recycleJuice()
                showCombo()
                raccoonMood = .cheer
            case .leveledUp:
                levelFanfare()
            case .gameOver:
                raccoonMood = .panic
            default: break
            }
        }
        onEvents?(ev)
    }

    private func showCombo() {
        guard engine.state.combo > 0, let comboLabel else { return }
        comboLabel.text = "COMBO x\(engine.state.combo)"
        comboLabel.alpha = 1
        comboLabel.setScale(0.6)
        comboLabel.removeAllActions()
        let hold = holdPresentation ? 2.8 : 0.45
        comboLabel.run(SKAction.sequence([
            SKAction.group([SKAction.scale(to: 1.15, duration: 0.12), SKAction.fadeAlpha(to: 1, duration: 0.08)]),
            SKAction.scale(to: 1.0, duration: 0.08),
            SKAction.wait(forDuration: hold),
            SKAction.fadeOut(withDuration: 0.25),
        ]))
    }

    private func bigCrushBanner(multiplier: Int = 3) {
        let label = SKLabelNode(fontNamed: "AvenirNext-Black")
        label.text = "BIG CRUSH x\(multiplier)"
        label.fontSize = 32
        label.fontColor = SKColor(red: 1, green: 0.3, blue: 0.85, alpha: 1)
        label.position = CGPoint(x: size.width / 2, y: size.height * 0.55)
        label.zPosition = 60
        label.setScale(0.4)
        addChild(label)
        let hold = holdPresentation ? 3.2 : 0.55
        label.run(SKAction.sequence([
            SKAction.group([SKAction.scale(to: 1.25, duration: 0.18), SKAction.fadeAlpha(to: 1, duration: 0.1)]),
            SKAction.scale(to: 1.05, duration: 0.1),
            SKAction.wait(forDuration: hold),
            SKAction.fadeOut(withDuration: 0.3),
            SKAction.removeFromParent(),
        ]))
    }

    /// Freeze-frame juice for evidence shot 03 / marketing crush.
    public func presentCrushMoment(rowCount: Int) {
        holdPresentation = true
        let vis = engine.state.board.config.visibleRows
        let hid = engine.state.board.config.hiddenRows
        let flashRows = max(1, min(rowCount, 4))
        for i in 0..<flashRows {
            let boardY = engine.state.board.config.rows - 1 - i
            let visY = boardY - hid
            guard visY >= 0, visY < vis else { continue }
            for x in 0..<engine.state.board.config.cols {
                guard let node = cellNodes[visY][x] else { continue }
                node.run(SKAction.repeatForever(SKAction.sequence([
                    SKAction.fadeAlpha(to: 0.35, duration: 0.12),
                    SKAction.fadeAlpha(to: 1.0, duration: 0.12),
                ])))
            }
        }
        // Hydraulic press bar.
        let press = SKSpriteNode(
            color: SKColor(red: 0.7, green: 0.75, blue: 0.85, alpha: 0.9),
            size: CGSize(width: cellSize().width * CGFloat(engine.state.board.config.cols) + 20, height: 18)
        )
        let origin = gridOrigin()
        let gridW = cellSize().width * CGFloat(engine.state.board.config.cols)
        press.position = CGPoint(x: origin.x + gridW / 2, y: size.height * 0.92)
        press.zPosition = 58
        addChild(press)
        let targetY = origin.y + cellSize().height * CGFloat(flashRows)
        press.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveTo(y: targetY, duration: 0.35),
            SKAction.wait(forDuration: 0.15),
            SKAction.moveTo(y: size.height * 0.92, duration: 0.25),
            SKAction.wait(forDuration: 0.2),
        ])))
        crushJuice(rows: Array(0..<flashRows))
        bigCrushBanner(multiplier: flashRows)
        // Keep particle bursts looping for the screenshot settle window.
        run(SKAction.repeat(SKAction.sequence([
            SKAction.run { [weak self] in self?.crushJuice(rows: Array(0..<flashRows)) },
            SKAction.wait(forDuration: 0.55),
        ]), count: 6))
    }

    /// Highlight a material chain + hold combo popup for evidence shot 04.
    public func presentRecycleMoment() {
        holdPresentation = true
        let hid = engine.state.board.config.hiddenRows
        let vis = engine.state.board.config.visibleRows
        for y in 0..<vis {
            for x in 0..<engine.state.board.config.cols {
                guard let cell = engine.state.board[x, y + hid],
                      cell.material == .metal,
                      let node = cellNodes[y][x] else { continue }
                let glow = SKSpriteNode(
                    color: SKColor(red: 0.1, green: 1, blue: 0.85, alpha: 0.35),
                    size: CGSize(width: node.size.width + 6, height: node.size.height + 6)
                )
                glow.position = node.position
                glow.zPosition = 7
                addChild(glow)
                glow.run(SKAction.repeatForever(SKAction.sequence([
                    SKAction.fadeAlpha(to: 0.15, duration: 0.2),
                    SKAction.fadeAlpha(to: 0.5, duration: 0.2),
                ])))
            }
        }
        showCombo()
        recycleJuice()
        let label = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        label.text = "RECYCLE CHAIN"
        label.fontSize = 22
        label.fontColor = SKColor(red: 0.2, green: 1, blue: 0.7, alpha: 1)
        label.position = CGPoint(x: size.width / 2, y: size.height * 0.72)
        label.zPosition = 61
        addChild(label)
        label.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.1),
            SKAction.wait(forDuration: 3.0),
            SKAction.fadeOut(withDuration: 0.3),
            SKAction.removeFromParent(),
        ]))
    }

    private func levelFanfare() {
        let label = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        label.text = "LEVEL \(engine.state.level)"
        label.fontSize = 22
        label.fontColor = .white
        label.position = CGPoint(x: size.width / 2, y: size.height * 0.6)
        label.zPosition = 60
        addChild(label)
        label.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.1),
            SKAction.wait(forDuration: 0.6),
            SKAction.fadeOut(withDuration: 0.3),
            SKAction.removeFromParent(),
        ]))
    }

    private func crushJuice(rows: [Int]) {
        run(SKAction.sequence([
            SKAction.moveBy(x: 0, y: -8, duration: 0.04),
            SKAction.moveBy(x: 3, y: 12, duration: 0.05),
            SKAction.moveBy(x: -3, y: -6, duration: 0.05),
            SKAction.move(to: .zero, duration: 0.06),
        ]))
        let flash = SKSpriteNode(color: SKColor(red: 1, green: 0.4, blue: 0.9, alpha: 0.28), size: size)
        flash.position = CGPoint(x: size.width / 2, y: size.height / 2)
        flash.zPosition = 55
        addChild(flash)
        flash.run(SKAction.sequence([SKAction.fadeOut(withDuration: 0.18), SKAction.removeFromParent()]))
        for _ in 0..<min(12, 4 * max(1, rows.count)) {
            let spark = SKSpriteNode(color: SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 1), size: CGSize(width: 3, height: 3))
            spark.position = CGPoint(x: size.width / 2 + CGFloat.random(in: -70...70), y: size.height * 0.4)
            spark.zPosition = 56
            addChild(spark)
            spark.run(SKAction.sequence([
                SKAction.group([
                    SKAction.moveBy(x: CGFloat.random(in: -50...50), y: CGFloat.random(in: 20...70), duration: 0.3),
                    SKAction.fadeOut(withDuration: 0.3),
                ]),
                SKAction.removeFromParent(),
            ]))
        }
    }

    private func recycleJuice() {
        let burst = SKSpriteNode(color: SKColor(red: 0.2, green: 0.95, blue: 0.7, alpha: 0.35), size: CGSize(width: 110, height: 110))
        burst.position = CGPoint(x: size.width / 2, y: size.height * 0.42)
        burst.zPosition = 54
        addChild(burst)
        burst.run(SKAction.sequence([
            SKAction.group([SKAction.scale(to: 1.5, duration: 0.2), SKAction.fadeOut(withDuration: 0.2)]),
            SKAction.removeFromParent(),
        ]))
    }

    public func render() {
        guard didBuild else { return }
        let hid = engine.state.board.config.hiddenRows
        let vis = engine.state.board.config.visibleRows
        let cs = cellSize()
        for y in 0..<vis {
            for x in 0..<engine.state.board.config.cols {
                let cell = engine.state.board[x, y + hid]
                guard let node = cellNodes[y][x] else { continue }
                if let cell {
                    if let t = tex(cell.piece.rawValue) {
                        node.texture = t
                        node.color = .white
                        node.colorBlendFactor = 0
                        node.size = CGSize(width: cs.width - cellPad, height: cs.height - cellPad)
                    } else {
                        node.texture = nil
                        node.color = fallbackColor(cell.material)
                        node.colorBlendFactor = 1
                    }
                    node.alpha = 1
                } else {
                    node.texture = nil
                    node.color = SKColor(white: 1, alpha: 0.04)
                    node.colorBlendFactor = 1
                    node.alpha = 1
                }
            }
        }
        activeNodes.forEach { $0.removeFromParent() }
        activeNodes.removeAll()
        if let p = engine.state.active {
            for (x, y) in p.cells where y >= hid {
                let n: SKSpriteNode
                if let t = tex(p.id.rawValue) {
                    n = SKSpriteNode(texture: t, size: CGSize(width: cs.width - cellPad, height: cs.height - cellPad))
                } else {
                    n = SKSpriteNode(color: fallbackColor(p.def.material), size: CGSize(width: cs.width - cellPad, height: cs.height - cellPad))
                }
                n.position = positionFor(x: x, boardY: y)
                n.zPosition = 8
                addChild(n)
                activeNodes.append(n)
            }
        }
    }

    private func fallbackColor(_ mat: Material) -> SKColor {
        switch mat {
        case .metal: return SKColor(red: 0.55, green: 0.62, blue: 0.72, alpha: 1)
        case .plastic: return SKColor(red: 0, green: 0.9, blue: 0.95, alpha: 1)
        case .paper: return SKColor(red: 0.85, green: 0.7, blue: 0.35, alpha: 1)
        case .glass: return SKColor(red: 0.45, green: 0.85, blue: 1, alpha: 0.9)
        case .rubber: return SKColor(red: 0.2, green: 0.2, blue: 0.22, alpha: 1)
        }
    }

    // MARK: - Gestures

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
            render()
        }
        let dy = p.y - start.y
        if dy < -cellSize().height * 0.8 {
            _ = engine.softDrop()
            render()
        }
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first, let start = touchStart else { return }
        let p = t.location(in: self)
        let dx = p.x - start.x
        let dy = p.y - start.y
        let dt = CACurrentMediaTime() - touchStartTime
        let dist = hypot(dx, dy)

        if dist < 12, dt < 0.35 {
            _ = engine.tryRotate()
            render()
        } else if dy < -55, abs(dy) > abs(dx), dt < 0.35 {
            engine.hardDrop()
            handleEvents()
            render()
            if engine.state.over { onGameOver?(engine.state) }
        } else if dy > 55, abs(dy) > abs(dx) {
            engine.stash()
            render()
        }
        touchStart = nil
    }

    public func moveLeft() { _ = engine.tryMove(dx: -1, dy: 0); render() }
    public func moveRight() { _ = engine.tryMove(dx: 1, dy: 0); render() }
    public func rotate() { _ = engine.tryRotate(); render() }
    public func soft() { _ = engine.softDrop(); render() }
    public func hard() {
        engine.hardDrop()
        handleEvents()
        render()
        if engine.state.over { onGameOver?(engine.state) }
    }
    public func stash() { engine.stash(); render() }
    public func magnet() {
        engine.useMagnet()
        handleEvents()
        render()
    }
    public func revive() {
        engine.revive()
        holdPresentation = false
        raccoonMood = .idle
        render()
    }
}
#else
import Foundation
#endif
