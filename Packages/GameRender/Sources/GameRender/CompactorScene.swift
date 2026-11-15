// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

#if canImport(SpriteKit)
import SpriteKit
import UIKit
import QuartzCore
import GameCore

/// SpriteKit playfield — texture atlases + baked glow art. No per-node glow/shader spam (jetsam-safe).
public final class CompactorScene: SKScene {
    public var engine = GameEngine(seed: UInt64.random(in: 1...UInt64.max))
    public var onGameOver: ((GameState) -> Void)?
    public var onEvents: (([GameEvent]) -> Void)?
    public var autoplay = false
    public var preferredFPS: Int = 60
    public private(set) var measuredFPS: Double = 60
    public var raccoonMood: RaccoonMood = .idle {
        didSet { updateRaccoon() }
    }

    public enum RaccoonMood { case idle, cheer, panic }

    private var world = SKNode()
    private var rainLayer = SKNode()
    private var boardLayer = SKNode()
    private var fxLayer = SKNode()
    private var cellNodes: [[SKSpriteNode?]] = []
    private var activeNodes: [SKSpriteNode] = []
    private var dumpsterFrame: SKSpriteNode?
    private var raccoon: SKSpriteNode?
    private var comboLabel: SKLabelNode?
    private var fpsLabel: SKLabelNode?
    private var gravityAcc: TimeInterval = 0
    private var lockAcc: TimeInterval = 0
    private var lastTime: TimeInterval = 0
    private var fpsSamples: [Double] = []
    private let cellPad: CGFloat = 1.5

    // Gestures
    private var touchStart: CGPoint?
    private var touchStartTime: TimeInterval = 0
    private var dragOriginX: Int = 0
    private var movedCols: Int = 0

    public override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.02, green: 0.02, blue: 0.05, alpha: 1)
        view.preferredFramesPerSecond = preferredFPS
        view.ignoresSiblingOrder = true
        view.isMultipleTouchEnabled = false
        removeAllChildren()
        addChild(world)
        world.addChild(rainLayer)
        world.addChild(boardLayer)
        world.addChild(fxLayer)
        buildBackground()
        rebuildGrid()
        buildHUD()
        render()
        startRain()
    }

    public func configureForProMotion(_ enabled: Bool) {
        preferredFPS = enabled ? 120 : 60
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
        engine.applyShotScenario(shot)
        gravityAcc = 0
        lockAcc = 0
        if shot == "recycle" { raccoonMood = .cheer }
        else if shot == "revive" || shot == "game-over" { raccoonMood = .panic }
        else { raccoonMood = .idle }
        render()
    }

    private func tex(_ name: String) -> SKTexture? {
        let t = SKTexture(imageNamed: name)
        // Unloaded placeholder is 1x1 — treat as missing when tiny.
        if t.size().width <= 1 { return nil }
        t.filteringMode = .nearest
        return t
    }

    private func buildBackground() {
        if let alley = tex("AlleyBackground") {
            let bg = SKSpriteNode(texture: alley)
            bg.size = size
            bg.position = CGPoint(x: size.width / 2, y: size.height / 2)
            bg.zPosition = -20
            bg.name = "alley"
            world.addChild(bg)
        } else {
            let bg = SKSpriteNode(color: SKColor(red: 0.05, green: 0.04, blue: 0.1, alpha: 1), size: size)
            bg.position = CGPoint(x: size.width / 2, y: size.height / 2)
            bg.zPosition = -20
            world.addChild(bg)
        }
    }

    private func startRain() {
        rainLayer.removeAllChildren()
        // Baked rain: short thin sprites, no glow nodes.
        for i in 0..<40 {
            let drop = SKSpriteNode(color: SKColor(white: 0.75, alpha: 0.28), size: CGSize(width: 1.5, height: CGFloat.random(in: 10...22)))
            drop.position = CGPoint(x: CGFloat.random(in: 0...size.width), y: CGFloat.random(in: 0...size.height))
            drop.zPosition = -10
            rainLayer.addChild(drop)
            let fall = SKAction.moveBy(x: -8, y: -size.height - 40, duration: Double.random(in: 0.55...1.1))
            let reset = SKAction.run { [weak drop, weak self] in
                guard let drop, let self else { return }
                drop.position = CGPoint(x: CGFloat.random(in: 0...self.size.width), y: self.size.height + 20)
            }
            drop.run(SKAction.repeatForever(SKAction.sequence([fall, reset])))
            drop.alpha = i % 3 == 0 ? 0.45 : 0.22
        }
        // Steam vent puffs — solid soft sprites, not shaders.
        for x: CGFloat in [0.18, 0.82] {
            let steam = SKSpriteNode(color: SKColor(white: 0.7, alpha: 0.12), size: CGSize(width: 40, height: 18))
            steam.position = CGPoint(x: size.width * x, y: size.height * 0.22)
            steam.zPosition = -8
            rainLayer.addChild(steam)
            steam.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.group([SKAction.fadeAlpha(to: 0.2, duration: 1.2), SKAction.moveBy(x: 0, y: 30, duration: 1.2)]),
                SKAction.group([SKAction.fadeAlpha(to: 0.05, duration: 1.0), SKAction.moveBy(x: 0, y: 20, duration: 1.0)]),
                SKAction.run { [weak steam, weak self] in
                    guard let steam, let self else { return }
                    steam.position.y = self.size.height * 0.22
                },
            ])))
        }
    }

    private func rebuildGrid() {
        boardLayer.removeAllChildren()
        cellNodes = []
        let cols = engine.state.board.config.cols
        let vis = engine.state.board.config.visibleRows
        cellNodes = Array(repeating: Array(repeating: nil, count: cols), count: vis)
        let cs = cellSize()
        let origin = gridOrigin()

        if let frameTex = tex("DumpsterFrame") {
            let frame = SKSpriteNode(texture: frameTex)
            let gridW = cs.width * CGFloat(cols)
            let gridH = cs.height * CGFloat(vis)
            frame.size = CGSize(width: gridW + 48, height: gridH + 64)
            frame.position = CGPoint(x: origin.x + gridW / 2, y: origin.y + gridH / 2 - 4)
            frame.zPosition = 0
            boardLayer.addChild(frame)
            dumpsterFrame = frame
        } else {
            let frame = SKShapeNode(
                rectOf: CGSize(width: cs.width * CGFloat(cols) + 16, height: cs.height * CGFloat(vis) + 16),
                cornerRadius: 10
            )
            frame.strokeColor = SKColor(red: 0, green: 0.95, blue: 1, alpha: 0.7)
            frame.fillColor = SKColor(red: 0.04, green: 0.05, blue: 0.09, alpha: 0.92)
            frame.lineWidth = 2
            frame.position = CGPoint(x: origin.x + cs.width * CGFloat(cols) / 2, y: origin.y + cs.height * CGFloat(vis) / 2)
            boardLayer.addChild(frame)
        }

        // Hydraulic rails (baked color bars — no glow FX nodes)
        for side in [-1, 1] {
            let rail = SKSpriteNode(color: SKColor(red: 0.9, green: 0.2, blue: 0.75, alpha: 0.55), size: CGSize(width: 6, height: cs.height * CGFloat(vis)))
            rail.position = CGPoint(
                x: origin.x + cs.width * CGFloat(cols) / 2 + CGFloat(side) * (cs.width * CGFloat(cols) / 2 + 18),
                y: origin.y + cs.height * CGFloat(vis) / 2
            )
            rail.zPosition = 2
            boardLayer.addChild(rail)
        }

        for y in 0..<vis {
            for x in 0..<cols {
                let n = SKSpriteNode(color: SKColor(white: 1, alpha: 0.03), size: CGSize(width: cs.width - cellPad, height: cs.height - cellPad))
                n.position = positionFor(x: x, boardY: y + engine.state.board.config.hiddenRows)
                n.zPosition = 3
                boardLayer.addChild(n)
                cellNodes[y][x] = n
            }
        }
    }

    private func buildHUD() {
        let rac: SKSpriteNode
        if let t = tex("RaccoonIdle") {
            rac = SKSpriteNode(texture: t, size: CGSize(width: 88, height: 88))
        } else {
            rac = SKSpriteNode(color: SKColor(white: 0.2, alpha: 1), size: CGSize(width: 72, height: 72))
        }
        rac.position = CGPoint(x: size.width - 58, y: size.height - 70)
        rac.zPosition = 40
        rac.name = "raccoon"
        world.addChild(rac)
        raccoon = rac

        let combo = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        combo.fontSize = 18
        combo.fontColor = SKColor(red: 0, green: 1, blue: 0.95, alpha: 1)
        combo.position = CGPoint(x: size.width / 2, y: size.height * 0.86)
        combo.zPosition = 45
        combo.alpha = 0
        world.addChild(combo)
        comboLabel = combo

        let fps = SKLabelNode(fontNamed: "Menlo-Bold")
        fps.fontSize = 10
        fps.fontColor = SKColor(white: 1, alpha: 0.35)
        fps.horizontalAlignmentMode = .left
        fps.position = CGPoint(x: 10, y: 8)
        fps.zPosition = 50
        fps.text = "60 fps"
        world.addChild(fps)
        fpsLabel = fps
    }

    private func updateRaccoon() {
        guard let raccoon else { return }
        let name: String
        switch raccoonMood {
        case .idle: name = "RaccoonIdle"
        case .cheer: name = "RaccoonCheer"
        case .panic: name = "RaccoonPanic"
        }
        if let t = tex(name) {
            raccoon.texture = t
            raccoon.size = CGSize(width: 88, height: 88)
        }
        raccoon.removeAllActions()
        switch raccoonMood {
        case .cheer:
            raccoon.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.scale(to: 1.08, duration: 0.15),
                SKAction.scale(to: 1.0, duration: 0.15),
            ])))
        case .panic:
            raccoon.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.moveBy(x: -3, y: 0, duration: 0.05),
                SKAction.moveBy(x: 6, y: 0, duration: 0.1),
                SKAction.moveBy(x: -3, y: 0, duration: 0.05),
            ])))
        case .idle:
            raccoon.setScale(1)
        }
    }

    private func cellSize() -> CGSize {
        let cols = CGFloat(engine.state.board.config.cols)
        let rows = CGFloat(engine.state.board.config.visibleRows)
        let w = size.width * 0.72 / cols
        let h = size.height * 0.62 / rows
        let s = min(w, h)
        return CGSize(width: s, height: s)
    }

    private func gridOrigin() -> CGPoint {
        let cs = cellSize()
        let cols = CGFloat(engine.state.board.config.cols)
        let rows = CGFloat(engine.state.board.config.visibleRows)
        let totalW = cs.width * cols
        let totalH = cs.height * rows
        return CGPoint(x: (size.width - totalW) / 2, y: (size.height - totalH) / 2 + size.height * 0.02)
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
            if dt > 0 {
                let fps = min(144, 1.0 / dt)
                fpsSamples.append(fps)
                if fpsSamples.count > 30 { fpsSamples.removeFirst() }
                measuredFPS = fpsSamples.reduce(0, +) / Double(fpsSamples.count)
                fpsLabel?.text = String(format: "%.0f fps", measuredFPS)
            }
        }
        lastTime = currentTime

        // Panic near top
        let filledTop = (0..<engine.state.board.config.cols).contains { x in
            engine.state.board[x, engine.state.board.config.hiddenRows + 2] != nil
        }
        if engine.state.over { raccoonMood = .panic }
        else if filledTop { raccoonMood = .panic }
        else if engine.state.combo >= 2 { raccoonMood = .cheer }

        if autoplay {
            gravityAcc += 1 / 60
            if gravityAcc > 0.14 {
                gravityAcc = 0
                engine.autoplayStep()
                handleEvents()
                if engine.state.over {
                    onGameOver?(engine.state)
                    if !autoplay { reset() }
                }
                render()
            }
            return
        }
        guard !engine.state.over, engine.state.active != nil else { return }
        let grav = max(0.08, 0.55 - Double(engine.state.level) * 0.03)
        gravityAcc += 1.0 / Double(max(30, preferredFPS))
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
                pulseActive()
            case .cleared(let rows, _, _):
                crushJuice(rows: rows)
                showCombo()
                if rows.count >= 3 {
                    raccoonMood = .cheer
                    bigCrushBanner()
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
        comboLabel.run(SKAction.sequence([
            SKAction.group([SKAction.scale(to: 1.15, duration: 0.12), SKAction.fadeAlpha(to: 1, duration: 0.08)]),
            SKAction.scale(to: 1.0, duration: 0.08),
            SKAction.wait(forDuration: 0.45),
            SKAction.fadeOut(withDuration: 0.25),
        ]))
    }

    private func bigCrushBanner() {
        let label = SKLabelNode(fontNamed: "AvenirNext-Black")
        label.text = "BIG CRUSH"
        label.fontSize = 28
        label.fontColor = SKColor(red: 1, green: 0.3, blue: 0.85, alpha: 1)
        label.position = CGPoint(x: size.width / 2, y: size.height * 0.55)
        label.zPosition = 60
        label.setScale(0.4)
        fxLayer.addChild(label)
        label.run(SKAction.sequence([
            SKAction.group([SKAction.scale(to: 1.2, duration: 0.18), SKAction.fadeAlpha(to: 1, duration: 0.1)]),
            SKAction.wait(forDuration: 0.5),
            SKAction.fadeOut(withDuration: 0.25),
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
        fxLayer.addChild(label)
        label.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.1),
            SKAction.wait(forDuration: 0.6),
            SKAction.fadeOut(withDuration: 0.3),
            SKAction.removeFromParent(),
        ]))
    }

    private func crushJuice(rows: [Int]) {
        // Hydraulic slam: shake world + press flash (single overlay, not per-cell glow).
        world.run(SKAction.sequence([
            SKAction.moveBy(x: 0, y: -10, duration: 0.04),
            SKAction.moveBy(x: 4, y: 14, duration: 0.05),
            SKAction.moveBy(x: -4, y: -6, duration: 0.05),
            SKAction.move(to: .zero, duration: 0.06),
        ]))
        let flash = SKSpriteNode(color: SKColor(red: 1, green: 0.4, blue: 0.9, alpha: 0.35), size: size)
        flash.position = CGPoint(x: size.width / 2, y: size.height / 2)
        flash.zPosition = 55
        fxLayer.addChild(flash)
        flash.run(SKAction.sequence([SKAction.fadeOut(withDuration: 0.18), SKAction.removeFromParent()]))
        // Sparks as tiny solid squares (baked, no glow).
        for _ in 0..<min(18, 6 * rows.count) {
            let spark = SKSpriteNode(color: SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 1), size: CGSize(width: 3, height: 3))
            spark.position = CGPoint(x: size.width / 2 + CGFloat.random(in: -80...80), y: size.height * 0.4)
            spark.zPosition = 56
            fxLayer.addChild(spark)
            spark.run(SKAction.sequence([
                SKAction.group([
                    SKAction.moveBy(x: CGFloat.random(in: -60...60), y: CGFloat.random(in: 20...90), duration: 0.35),
                    SKAction.fadeOut(withDuration: 0.35),
                ]),
                SKAction.removeFromParent(),
            ]))
        }
    }

    private func recycleJuice() {
        let burst = SKSpriteNode(color: SKColor(red: 0.2, green: 0.95, blue: 0.7, alpha: 0.4), size: CGSize(width: 120, height: 120))
        burst.position = CGPoint(x: size.width / 2, y: size.height * 0.42)
        burst.zPosition = 54
        fxLayer.addChild(burst)
        burst.run(SKAction.sequence([
            SKAction.group([SKAction.scale(to: 1.6, duration: 0.22), SKAction.fadeOut(withDuration: 0.22)]),
            SKAction.removeFromParent(),
        ]))
    }

    private func pulseActive() {
        for n in activeNodes {
            n.run(SKAction.sequence([
                SKAction.scale(to: 1.12, duration: 0.05),
                SKAction.scale(to: 1.0, duration: 0.08),
            ]))
        }
    }

    public func render() {
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
                    node.color = SKColor(white: 1, alpha: 0.03)
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
                // Cyan rim via slight scale shadow sibling avoided — use outline color blend lightly.
                boardLayer.addChild(n)
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

    // MARK: - Gestures (touch)

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        touchStart = t.location(in: self)
        touchStartTime = CACurrentMediaTime()
        dragOriginX = engine.state.active?.x ?? 0
        movedCols = 0
    }

    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first, let start = touchStart, engine.state.active != nil else { return }
        let p = t.location(in: self)
        let dx = p.x - start.x
        let colW = cellSize().width
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
            // Flick down → hard drop
            engine.hardDrop()
            handleEvents()
            render()
            if engine.state.over { onGameOver?(engine.state) }
        } else if dy > 55, abs(dy) > abs(dx) {
            // Swipe up → stash
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
        raccoonMood = .idle
        render()
    }
}
#else
import Foundation
#endif
