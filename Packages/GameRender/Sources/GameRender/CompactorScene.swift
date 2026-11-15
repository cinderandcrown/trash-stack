// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

#if canImport(SpriteKit)
import SpriteKit
import GameCore

/// SpriteKit playfield — baked colors, no per-node glow / heavy shaders (jetsam-safe).
public final class CompactorScene: SKScene {
    public var engine = GameEngine(seed: UInt64.random(in: 1...UInt64.max))
    public var onGameOver: ((GameState) -> Void)?
    public var autoplay = false
    public var preferredFPS: Int = 60

    private var cellNodes: [[SKShapeNode?]] = []
    private var activeNodes: [SKShapeNode] = []
    private var gravityAcc: TimeInterval = 0
    private var lockAcc: TimeInterval = 0
    private let cellPad: CGFloat = 1

    public override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.03, green: 0.03, blue: 0.06, alpha: 1)
        view.preferredFramesPerSecond = preferredFPS
        view.ignoresSiblingOrder = true
        rebuildGrid()
        render()
    }

    public func configureForProMotion(_ enabled: Bool) {
        preferredFPS = enabled ? 120 : 60
        view?.preferredFramesPerSecond = preferredFPS
    }

    public func reset(seed: UInt64 = UInt64.random(in: 1...999_999)) {
        engine = GameEngine(seed: seed)
        gravityAcc = 0
        lockAcc = 0
        render()
    }

    private func rebuildGrid() {
        removeAllChildren()
        let cols = engine.state.board.config.cols
        let vis = engine.state.board.config.visibleRows
        cellNodes = Array(repeating: Array(repeating: nil, count: cols), count: vis)
        let size = cellSize()
        let origin = gridOrigin()
        let frame = SKShapeNode(
            rectOf: CGSize(width: size.width * CGFloat(cols) + 8, height: size.height * CGFloat(vis) + 8),
            cornerRadius: 8
        )
        frame.strokeColor = SKColor(red: 0, green: 0.96, blue: 1, alpha: 0.55)
        frame.fillColor = SKColor(red: 0.05, green: 0.06, blue: 0.1, alpha: 0.95)
        frame.lineWidth = 2
        frame.position = CGPoint(
            x: origin.x + size.width * CGFloat(cols) / 2,
            y: origin.y + size.height * CGFloat(vis) / 2
        )
        frame.zPosition = 0
        addChild(frame)

        for y in 0..<vis {
            for x in 0..<cols {
                let n = SKShapeNode(
                    rectOf: CGSize(width: size.width - cellPad, height: size.height - cellPad),
                    cornerRadius: 3
                )
                n.fillColor = .clear
                n.strokeColor = SKColor(white: 1, alpha: 0.04)
                n.lineWidth = 1
                n.position = positionFor(x: x, boardY: y + engine.state.board.config.hiddenRows)
                n.zPosition = 1
                addChild(n)
                cellNodes[y][x] = n
            }
        }
    }

    private func cellSize() -> CGSize {
        let cols = CGFloat(engine.state.board.config.cols)
        let rows = CGFloat(engine.state.board.config.visibleRows)
        let w = size.width * 0.78 / cols
        let h = size.height * 0.72 / rows
        let s = min(w, h)
        return CGSize(width: s, height: s)
    }

    private func gridOrigin() -> CGPoint {
        let cs = cellSize()
        let cols = CGFloat(engine.state.board.config.cols)
        let rows = CGFloat(engine.state.board.config.visibleRows)
        let totalW = cs.width * cols
        let totalH = cs.height * rows
        return CGPoint(x: (size.width - totalW) / 2, y: (size.height - totalH) / 2 + size.height * 0.04)
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
        if autoplay {
            gravityAcc += 1 / 60
            if gravityAcc > 0.12 {
                gravityAcc = 0
                engine.autoplayStep()
                if engine.state.over {
                    onGameOver?(engine.state)
                    reset()
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
                    if engine.state.over { onGameOver?(engine.state) }
                }
            } else {
                lockAcc = 0
            }
            render()
        }
    }

    public func render() {
        let hid = engine.state.board.config.hiddenRows
        let vis = engine.state.board.config.visibleRows
        for y in 0..<vis {
            for x in 0..<engine.state.board.config.cols {
                let cell = engine.state.board[x, y + hid]
                let node = cellNodes[y][x]
                if let cell {
                    node?.fillColor = color(for: cell.material)
                    node?.strokeColor = SKColor(white: 1, alpha: 0.15)
                } else {
                    node?.fillColor = .clear
                    node?.strokeColor = SKColor(white: 1, alpha: 0.04)
                }
            }
        }
        activeNodes.forEach { $0.removeFromParent() }
        activeNodes.removeAll()
        if let p = engine.state.active {
            let cs = cellSize()
            for (x, y) in p.cells where y >= hid {
                let n = SKShapeNode(
                    rectOf: CGSize(width: cs.width - cellPad, height: cs.height - cellPad),
                    cornerRadius: 3
                )
                n.fillColor = color(for: p.def.material)
                n.strokeColor = SKColor(red: 0, green: 0.96, blue: 1, alpha: 0.7)
                n.lineWidth = 1.5
                n.position = positionFor(x: x, boardY: y)
                n.zPosition = 5
                addChild(n)
                activeNodes.append(n)
            }
        }
    }

    private func color(for mat: Material) -> SKColor {
        switch mat {
        case .metal: return SKColor(red: 0.55, green: 0.62, blue: 0.72, alpha: 1)
        case .plastic: return SKColor(red: 0, green: 0.9, blue: 0.95, alpha: 1)
        case .paper: return SKColor(red: 0.85, green: 0.7, blue: 0.35, alpha: 1)
        case .glass: return SKColor(red: 0.45, green: 0.85, blue: 1, alpha: 0.85)
        case .rubber: return SKColor(red: 0.2, green: 0.2, blue: 0.22, alpha: 1)
        }
    }

    public func moveLeft() { _ = engine.tryMove(dx: -1, dy: 0); render() }
    public func moveRight() { _ = engine.tryMove(dx: 1, dy: 0); render() }
    public func rotate() { _ = engine.tryRotate(); render() }
    public func soft() { _ = engine.softDrop(); render() }
    public func hard() {
        engine.hardDrop()
        render()
        if engine.state.over { onGameOver?(engine.state) }
    }
    public func stash() { engine.stash(); render() }
    public func magnet() { engine.useMagnet(); render() }

    public func revive() {
        engine.revive()
        render()
    }
}
#endif
