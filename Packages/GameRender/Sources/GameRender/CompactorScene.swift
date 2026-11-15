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
    public var preferredFPS: Int = 60
    public private(set) var measuredFPS: Double = 60
    public var raccoonMood: RaccoonMood = .idle

    public enum RaccoonMood: Equatable { case idle, cheer, panic }

    private var cellNodes: [[SKSpriteNode?]] = []
    private var activeNodes: [SKSpriteNode] = []
    private var comboLabel: SKLabelNode?
    private var crushLabel: SKLabelNode?
    private var fpsLabel: SKLabelNode?
    private var alleyNode: SKSpriteNode?
    private var gravityAcc: TimeInterval = 0
    private var lockAcc: TimeInterval = 0
    private var lastTime: TimeInterval = 0
    private var fpsSamples: [Double] = []
    private var didBuild = false
    private let cellPad: CGFloat = 0.5
    private var holdPresentation = false
    private var pendingShot: String?
    private var popupQueue: [(String, SKColor)] = []
    private var popupBusy = false
    private var fallTween: CGFloat = 0
    private var tweening = false

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
        holdPresentation = ["compactor", "press", "recycle", "game", "gameplay"].contains(shot)
        if shot == "recycle" { raccoonMood = .cheer }
        else if shot == "compactor" || shot == "press" { raccoonMood = .cheer }
        else if shot == "revive" || shot == "game-over" { raccoonMood = .panic }
        else { raccoonMood = .idle }
        if didBuild {
            render(immediate: true)
            presentPendingShotJuice()
        }
    }

    /// Continuous autoplay demo — no instant board swaps.
    public func startDemoChoreography(onGameOverBeat: @escaping () -> Void) {
        autoplay = true
        removeAction(forKey: "demoChoreography")
        // Soft prompts only: ensure press eventually, snatch once, then natural top-out.
        run(SKAction.sequence([
            SKAction.wait(forDuration: 18),
            SKAction.run { [weak self] in
                guard let self else { return }
                self.engine.fillPressMeter()
                _ = self.engine.slamPress()
                self.handleEvents()
                self.render(immediate: false)
            },
            SKAction.wait(forDuration: 10),
            SKAction.run { [weak self] in
                guard let self else { return }
                if self.engine.state.snatchAvailable {
                    _ = self.engine.snatchRandom()
                    self.handleEvents()
                    self.render(immediate: false)
                }
            },
            SKAction.wait(forDuration: 22),
            SKAction.run { [weak self] in
                guard let self else { return }
                if !self.engine.state.over {
                    self.engine.applyShotScenario("revive")
                    self.render(immediate: true)
                    self.raccoonMood = .panic
                }
                onGameOverBeat()
            },
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
        alleyNode = nil
        comboLabel = nil
        crushLabel = nil
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

        let combo = makePopupLabel(fontSize: 24)
        combo.position = CGPoint(x: size.width / 2, y: size.height * 0.78)
        combo.zPosition = 45
        combo.alpha = 0
        addChild(combo)
        comboLabel = combo

        let crush = makePopupLabel(fontSize: 28)
        crush.position = CGPoint(x: size.width / 2, y: size.height * 0.68)
        crush.zPosition = 46
        crush.alpha = 0
        addChild(crush)
        crushLabel = crush

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
    }

    private func makePopupLabel(fontSize: CGFloat) -> SKLabelNode {
        let label = SKLabelNode(fontNamed: "AvenirNext-Black")
        label.fontSize = fontSize
        label.fontColor = .white
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        // Outline via shadow clones
        return label
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
            engine.state.board[x, engine.state.board.config.hiddenRows] != nil
        }
        let nextMood: RaccoonMood
        if engine.state.over || filledTop { nextMood = .panic }
        else if engine.state.combo >= 2 { nextMood = .cheer }
        else { nextMood = .idle }
        if nextMood != raccoonMood { raccoonMood = nextMood }

        if tweening {
            fallTween = min(1, fallTween + CGFloat(1.0 / 8.0))
            updateActivePositions(fraction: fallTween)
            if fallTween >= 1 { tweening = false; fallTween = 0 }
        }

        if autoplay {
            gravityAcc += 1 / 60
            if gravityAcc > 0.28 {
                gravityAcc = 0
                engine.autoplayStep()
                handleEvents()
                if engine.state.over { onGameOver?(engine.state) }
                beginFallTween()
                render(immediate: false)
            }
            return
        }
        guard !engine.state.over, engine.state.active != nil else { return }
        let grav = max(0.12, 0.62 - Double(engine.state.level) * 0.03)
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
                beginFallTween()
            }
            render(immediate: false)
        }
    }

    private func beginFallTween() {
        fallTween = 0
        tweening = true
    }

    private func updateActivePositions(fraction: CGFloat) {
        guard let p = engine.state.active else { return }
        let cs = cellSize()
        let lift = (1 - fraction) * cs.height
        for (i, cell) in p.cells.enumerated() where i < activeNodes.count {
            activeNodes[i].position = positionFor(x: cell.0, boardY: cell.1, yOffset: lift)
        }
    }

    private func handleEvents() {
        let ev = engine.drainEvents()
        for e in ev {
            switch e {
            case .locked:
                break
            case .recycled(_, let cells, _, _, _):
                recycleJuice(cellCount: cells)
                enqueuePopup("RECYCLE", color: SKColor(red: 0.2, green: 1, blue: 0.75, alpha: 1), slot: .combo)
                if engine.state.combo >= 2 {
                    enqueuePopup("CHAIN x\(engine.state.combo)", color: SKColor(red: 0, green: 1, blue: 0.95, alpha: 1), slot: .combo)
                    raccoonMood = .cheer
                }
            case .pressed(let cells, _, _):
                pressJuice(cells: cells)
                enqueuePopup("PRESS SLAM", color: SKColor(red: 1, green: 0.35, blue: 0.85, alpha: 1), slot: .banner)
                raccoonMood = .cheer
            case .orderCompleted(let order):
                enqueuePopup("ORDER DONE", color: SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 1), slot: .banner)
                _ = order
            case .snatchUsed:
                enqueuePopup("SNATCH", color: SKColor(red: 1, green: 0.6, blue: 0.2, alpha: 1), slot: .combo)
            case .leveledUp(let lvl):
                enqueuePopup("LEVEL \(lvl)", color: .white, slot: .banner)
            case .gameOver:
                raccoonMood = .panic
            default: break
            }
        }
        onEvents?(ev)
    }

    private enum PopupSlot { case combo, banner }

    private func enqueuePopup(_ text: String, color: SKColor, slot: PopupSlot) {
        popupQueue.append((text, color))
        drainPopupQueue(preferred: slot)
    }

    private func drainPopupQueue(preferred: PopupSlot) {
        guard !popupBusy, let next = popupQueue.first else { return }
        popupQueue.removeFirst()
        popupBusy = true
        let label = preferred == .combo ? comboLabel : crushLabel
        let other = preferred == .combo ? crushLabel : comboLabel
        // Keep slots from overlapping: if other is visible, use opposite slot.
        let target = (label?.alpha ?? 0) > 0.2 ? other : label
        guard let target else { popupBusy = false; return }
        target.removeAllActions()
        target.text = next.0
        target.fontColor = next.1
        target.alpha = 1
        target.setScale(0.45)
        // Glow via shadow
        target.fontName = "AvenirNext-Black"
        let hold = holdPresentation ? 2.4 : 0.7
        target.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 1.18, duration: 0.12),
                SKAction.fadeAlpha(to: 1, duration: 0.08),
            ]),
            SKAction.scale(to: 1.0, duration: 0.08),
            SKAction.wait(forDuration: hold),
            SKAction.group([SKAction.fadeOut(withDuration: 0.28), SKAction.scale(to: 0.8, duration: 0.28)]),
            SKAction.run { [weak self] in
                self?.popupBusy = false
                self?.drainPopupQueue(preferred: preferred)
            },
        ]))
    }

    public func presentPressMoment() {
        holdPresentation = true
        engine.fillPressMeter()
        pressJuice(cells: 16)
        enqueuePopup("PRESS SLAM", color: SKColor(red: 1, green: 0.35, blue: 0.85, alpha: 1), slot: .banner)
        // Hydraulic bar
        let press = SKSpriteNode(
            color: SKColor(red: 0.75, green: 0.8, blue: 0.9, alpha: 0.95),
            size: CGSize(width: cellSize().width * CGFloat(engine.state.board.config.cols) + 20, height: 16)
        )
        let origin = gridOrigin()
        let gridW = cellSize().width * CGFloat(engine.state.board.config.cols)
        press.position = CGPoint(x: origin.x + gridW / 2, y: size.height * 0.92)
        press.zPosition = 58
        addChild(press)
        let targetY = origin.y + cellSize().height * 2
        press.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveTo(y: targetY, duration: 0.32),
            SKAction.wait(forDuration: 0.12),
            SKAction.moveTo(y: size.height * 0.92, duration: 0.22),
            SKAction.wait(forDuration: 0.18),
        ])))
    }

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
        enqueuePopup("RECYCLE CHAIN", color: SKColor(red: 0.2, green: 1, blue: 0.7, alpha: 1), slot: .banner)
        enqueuePopup("COMBO x3", color: SKColor(red: 0, green: 1, blue: 0.95, alpha: 1), slot: .combo)
        recycleJuice(cellCount: 8)
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

    private func recycleJuice(cellCount: Int) {
        // Chute suction: particles stream toward a side chute.
        let chute = CGPoint(x: size.width * 0.92, y: size.height * 0.55)
        spawnParticle(named: "SparkTeal", at: CGPoint(x: size.width / 2, y: size.height * 0.42), count: min(16, 4 + cellCount))
        for _ in 0..<min(10, 3 + cellCount / 2) {
            let mote: SKSpriteNode
            if let t = tex("SparkTeal") {
                mote = SKSpriteNode(texture: t, size: CGSize(width: 14, height: 14))
                mote.blendMode = .alpha
            } else {
                mote = SKSpriteNode(color: SKColor(red: 0.2, green: 1, blue: 0.8, alpha: 0.9), size: CGSize(width: 5, height: 5))
            }
            mote.position = CGPoint(
                x: size.width / 2 + CGFloat.random(in: -60...60),
                y: size.height * 0.4 + CGFloat.random(in: -40...40)
            )
            mote.zPosition = 57
            addChild(mote)
            mote.run(SKAction.sequence([
                SKAction.group([
                    SKAction.move(to: chute, duration: 0.28),
                    SKAction.scale(to: 0.2, duration: 0.28),
                    SKAction.fadeOut(withDuration: 0.28),
                ]),
                SKAction.removeFromParent(),
            ]))
        }
        if engine.state.combo >= 3 {
            // Screen pulse on big chains.
            let pulse = SKSpriteNode(color: SKColor(red: 0.1, green: 1, blue: 0.9, alpha: 0.2), size: size)
            pulse.position = CGPoint(x: size.width / 2, y: size.height / 2)
            pulse.zPosition = 54
            pulse.blendMode = .alpha
            addChild(pulse)
            pulse.run(SKAction.sequence([
                SKAction.group([SKAction.fadeOut(withDuration: 0.22), SKAction.scale(to: 1.08, duration: 0.22)]),
                SKAction.removeFromParent(),
            ]))
            screenShake(strength: 6)
        }
    }

    private func pressJuice(cells: Int) {
        screenShake(strength: cells >= 10 ? 12 : 7)
        // Squash bottom band
        let hid = engine.state.board.config.hiddenRows
        let vis = engine.state.board.config.visibleRows
        for i in 0..<2 {
            let boardY = engine.state.board.config.rows - 1 - i
            let visY = boardY - hid
            guard visY >= 0, visY < vis else { continue }
            for x in 0..<engine.state.board.config.cols {
                guard let node = cellNodes[visY][x] else { continue }
                node.run(SKAction.sequence([
                    SKAction.group([
                        SKAction.scaleY(to: 0.35, duration: 0.1),
                        SKAction.fadeAlpha(to: 0.5, duration: 0.1),
                    ]),
                    SKAction.group([
                        SKAction.scaleY(to: 1.0, duration: 0.15),
                        SKAction.fadeAlpha(to: 1, duration: 0.15),
                    ]),
                ]))
            }
        }
        let flash = SKSpriteNode(color: SKColor(red: 1, green: 0.45, blue: 0.9, alpha: 0.22), size: size)
        flash.position = CGPoint(x: size.width / 2, y: size.height / 2)
        flash.zPosition = 55
        flash.blendMode = .alpha
        addChild(flash)
        flash.run(SKAction.sequence([SKAction.fadeOut(withDuration: 0.2), SKAction.removeFromParent()]))
        spawnParticle(named: "SparkMagenta", at: CGPoint(x: size.width / 2, y: gridOrigin().y + cellSize().height), count: min(20, 6 + cells))
        // Scrap shower
        spawnParticle(named: "DebrisMetal", at: CGPoint(x: size.width / 2, y: gridOrigin().y + cellSize().height * 2), count: min(14, 4 + cells / 2))
        spawnParticle(named: "SparkGold", at: CGPoint(x: size.width * 0.5, y: gridOrigin().y + cellSize().height * 1.5), count: 8)
    }

    public func render(immediate: Bool = true) {
        guard didBuild else { return }
        let hid = engine.state.board.config.hiddenRows
        let vis = engine.state.board.config.visibleRows
        let cs = cellSize()
        for y in 0..<vis {
            for x in 0..<engine.state.board.config.cols {
                let cell = engine.state.board[x, y + hid]
                guard let node = cellNodes[y][x] else { continue }
                if let cell {
                    let name = JunkCatalog.textureName(for: cell.piece)
                    if let t = tex(name) {
                        node.texture = t
                        node.color = .white
                        node.colorBlendFactor = 0
                        node.size = CGSize(width: cs.width - cellPad, height: cs.height - cellPad)
                    } else {
                        node.texture = nil
                        node.color = fallbackColor(cell.material)
                        node.colorBlendFactor = 1
                    }
                    node.alpha = cell.sticky ? 0.7 : 1
                    let dest = positionFor(x: x, boardY: y + hid)
                    if immediate {
                        node.removeAction(forKey: "settle")
                        node.position = dest
                    } else if hypot(node.position.x - dest.x, node.position.y - dest.y) > 1 {
                        node.removeAction(forKey: "settle")
                        let move = SKAction.move(to: dest, duration: 0.14)
                        move.timingMode = .easeInEaseOut
                        node.run(move, withKey: "settle")
                    }
                } else {
                    node.texture = nil
                    node.color = SKColor(white: 1, alpha: 0.04)
                    node.colorBlendFactor = 1
                    node.alpha = 1
                    node.setScale(1)
                }
            }
        }
        activeNodes.forEach { $0.removeFromParent() }
        activeNodes.removeAll()
        if let p = engine.state.active {
            let lift: CGFloat = tweening ? (1 - fallTween) * cs.height : 0
            for (x, y) in p.cells where y >= hid {
                let n: SKSpriteNode
                let name = JunkCatalog.textureName(for: p.id)
                if let t = tex(name) {
                    n = SKSpriteNode(texture: t, size: CGSize(width: cs.width - cellPad, height: cs.height - cellPad))
                } else {
                    n = SKSpriteNode(color: fallbackColor(p.def.material), size: CGSize(width: cs.width - cellPad, height: cs.height - cellPad))
                }
                n.position = positionFor(x: x, boardY: y, yOffset: lift)
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
            render(immediate: true)
        }
        let dy = p.y - start.y
        if dy < -cellSize().height * 0.8 {
            _ = engine.softDrop()
            beginFallTween()
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

        if dist < 12, dt < 0.35 {
            _ = engine.tryRotate()
            render(immediate: true)
        } else if dy < -55, abs(dy) > abs(dx), dt < 0.35 {
            engine.hardDrop()
            handleEvents()
            render(immediate: false)
            if engine.state.over { onGameOver?(engine.state) }
        } else if dy > 55, abs(dy) > abs(dx) {
            engine.stash()
            render(immediate: true)
        }
        touchStart = nil
    }

    public func moveLeft() { _ = engine.tryMove(dx: -1, dy: 0); render(immediate: true) }
    public func moveRight() { _ = engine.tryMove(dx: 1, dy: 0); render(immediate: true) }
    public func rotate() { _ = engine.tryRotate(); render(immediate: true) }
    public func soft() { _ = engine.softDrop(); beginFallTween(); render(immediate: false) }
    public func hard() {
        engine.hardDrop()
        handleEvents()
        render(immediate: false)
        if engine.state.over { onGameOver?(engine.state) }
    }
    public func stash() { engine.stash(); render(immediate: true) }
    public func magnet() {
        // Legacy hook → Snatch random for HUD button compat during transition.
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
        holdPresentation = false
        raccoonMood = .idle
        render(immediate: true)
    }
}
#else
import Foundation
#endif
