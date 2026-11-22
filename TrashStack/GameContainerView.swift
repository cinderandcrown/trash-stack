// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import SwiftUI
import SpriteKit
import GameRender
import GameCore
import Services

struct GameContainerView: View {
    @Binding var screen: AppScreen
    @Binding var showNotifPrompt: Bool
    @Binding var playMode: PlayMode
    var onDailyFinished: ((Int, String) -> Void)? = nil
    var onStreakReward: ((Int, Int, Int) -> Void)? = nil
    @EnvironmentObject var profile: PlayerProfile
    @Environment(\.scenePhase) private var scenePhase
    @State private var scene = CompactorScene(size: CGSize(width: 390, height: 780))
    @State private var showContinue = false
    @State private var lastState: GameState?
    @State private var continued = false
    @State private var hudScore = 0
    @State private var displayScore = 0
    @State private var hudLevel = 1
    @State private var raccoonMood: CompactorScene.RaccoonMood = .idle
    @State private var raccoonBounce: CGFloat = 1.0
    @State private var pauseGate = PauseGate()
    @State private var scoreAnimTask: Task<Void, Never>?
    @State private var sheetScoreAnimTask: Task<Void, Never>?
    @State private var pressMeter = 0
    @State private var pressMax = 6
    @State private var snatchReady = true
    @State private var orders: [OrderTicket] = []
    @State private var preview: [JunkID] = []
    @State private var holdItem: JunkID? = nil
    @State private var nearMiss = false
    @State private var toastText: String? = nil
    @State private var toastQueue: [String] = []
    @State private var toastTask: Task<Void, Never>? = nil
    @State private var snatchPressed = false
    @State private var showSnatchTip = false
    @State private var completedOrderFlash: String? = nil
    @State private var rewardFly: String? = nil
    /// Locked at top-out — never a stale HUD or smoke-staged value.
    @State private var overScore = 0
    @State private var sheetScore = 0
    @State private var overBestBefore = 0
    @State private var isNewBest = false
    /// First-launch how-to (skippable) — replaces the old TutorialView gate.
    @State private var showHowTo = false
    @State private var showGestureHint = false
    @State private var gestureHintTask: Task<Void, Never>?
    @State private var traySlots: [JunkID?] = [nil, nil, nil]
    @State private var movesLeft = 0
    @State private var teachHint: String? = nil
    @State private var starsEarned = 0
    @State private var showLevelWin = false
    /// Stars waiting to show after CHAIN / fly juice finishes.
    @State private var pendingWinStars: Int? = nil
    @State private var winPresentTask: Task<Void, Never>? = nil
    @State private var boostMagnet = 0
    @State private var boostCrusher = 0
    @State private var boostSlam = 0
    @State private var boostShuffle = 0
    @State private var selectedTray: Int? = nil
    /// Global frame of the SK board — tray drag converts finger → board cell with this.
    @State private var boardFrameGlobal: CGRect = .zero

    private var isPaused: Bool { pauseGate.isPaused }

    /// Demo / CI smoke autoplay — must not resign-pause (recordVideo would freeze the clip).
    private static var isDemoOrSmokeAutoplay: Bool {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-autoplay") { return true }
        if let shot = PlayerProfile.shotArgument(), shot == "demo" || shot == "autoplay" { return true }
        if let active = UserDefaults.standard.string(forKey: "trashStack.shotActive"),
           active == "demo" || active == "autoplay" {
            return true
        }
        return false
    }

    var body: some View {
        ZStack {
            NeonTheme.playChrome.ignoresSafeArea()
            VStack(spacing: 0) {
                leanHudBar
                    .padding(.horizontal, 8)

                // Board fills remaining height; ~8px side margins via scene cellSize.
                // UIKit SKView host — SwiftUI SpriteView+clipShape painted a flat grey void.
                BoardSKView(scene: scene)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .accessibilityIdentifier("gameBoard")
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .preference(
                                    key: BoardGlobalFrameKey.self,
                                    value: geo.frame(in: .global)
                                )
                                .onAppear { boardFrameGlobal = geo.frame(in: .global) }
                                .onChange(of: geo.size) { _, _ in
                                    boardFrameGlobal = geo.frame(in: .global)
                                }
                        }
                    )
                    .onPreferenceChange(BoardGlobalFrameKey.self) { boardFrameGlobal = $0 }
                    .overlay(alignment: .topTrailing) {
                        // Classic NEXT/HOLD only — turn-based uses the bottom tray.
                        if !scene.engine.state.isTurnBased {
                            miniNextHold
                                .padding(.trailing, 6)
                                .padding(.top, 6)
                        }
                    }
                    // Tap-to-place seats (player feature): tap a tray piece, then tap a board cell.
                    .overlay {
                        boardTapToPlaceSeats
                    }
                    .overlay(alignment: .top) {
                        if nearMiss || (lastState?.over == true) {
                            Text(lastState?.over == true ? "BIN OVERFLOW" : "BIN ALMOST FULL")
                                .font(.caption.weight(.black))
                                .foregroundStyle(NeonTheme.magenta)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.55))
                                .clipShape(Capsule())
                                .padding(.top, 8)
                        }
                    }
                    .overlay(alignment: .top) {
                        // One instruction only — never stack a generic tip over the level teach hint.
                        if showGestureHint, teachHint == nil || teachHint?.isEmpty == true {
                            Text(scene.engine.state.isTurnBased
                                 ? "Tap a tray piece, then tap the board"
                                 : "Tap rotate · drag move · swipe ↓ drop · ↑ hold")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(8)
                                .background(Color.black.opacity(0.7))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .padding(.top, 36)
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 8)

                if profile.classicButtons {
                    classicPad
                }

                // Tray + boosters fully below the dumpster neon lip (turn-based only).
                if scene.engine.state.isTurnBased {
                    Color.clear.frame(height: 12)
                    turnBasedTray
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .layoutPriority(1)
                        .background(NeonTheme.playChrome)
                }
            }
            .safeAreaPadding(.top, 8)
            .safeAreaPadding(.bottom, 10)
            .allowsHitTesting(!showHowTo && !isPaused)

            // Toasts above HUD / buttons — never behind the control layer.
            if toastText != nil {
                VStack {
                    toastBanner
                        .padding(.top, 56)
                    Spacer()
                }
                .allowsHitTesting(false)
                .zIndex(60)
            }

            if showHowTo {
                HowToPlayOverlay {
                    dismissHowTo()
                }
                .transition(.opacity)
                .zIndex(40)
            }

            if showLevelWin {
                ZStack {
                    Color.black.opacity(0.72).ignoresSafeArea()
                    VStack(spacing: 14) {
                        Text("LEVEL CLEAR")
                            .font(.title.weight(.black))
                            .foregroundStyle(NeonTheme.teal)
                        Text(String(repeating: "★", count: max(1, starsEarned))
                              + String(repeating: "☆", count: max(0, 3 - starsEarned)))
                            .font(.largeTitle)
                            .foregroundStyle(NeonTheme.gold)
                            .accessibilityIdentifier("levelStars")
                        Text(orders.first?.label ?? "Goal done")
                            .font(.caption)
                            .foregroundStyle(NeonTheme.muted)
                        Button {
                            openLevelMapAfterWin()
                        } label: {
                            Text("LEVEL MAP")
                                .font(.headline.weight(.black))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(NeonTheme.teal)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("levelMapButton")
                        Button {
                            let cleared = max(1, scene.engine.state.levelId)
                            let next = min(20, cleared + 1)
                            showLevelWin = false
                            profile.shiftProgress = max(profile.shiftProgress, cleared)
                            profile.persist()
                            UserDefaults.standard.set("\(next)", forKey: "trashStack.shiftLevel")
                            scene.startShiftLevel(next)
                            syncHUD()
                        } label: {
                            Text(scene.engine.state.levelId >= 20 ? "Done" : "Next level")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(NeonTheme.muted)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("nextLevelButton")
                    }
                    .padding(24)
                    .background(NeonTheme.playChrome)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(28)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("levelWinOverlay")
                }
                .zIndex(80)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("levelWinOverlay")
            }

            if showSnatchTip {
                Text("SNATCH — Bandit grabs a sticky block")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(NeonTheme.magenta.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.bottom, 120)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .transition(.opacity)
                    .zIndex(35)
            }

            // Idempotent pause overlay — NOT a sheet (sheets flickered on TestFlight).
            if isPaused {
                pauseOverlay
                    .transition(.opacity)
                    .zIndex(50)
            }

            // Game-over is an overlay (not a sheet) so sim screenshots always catch
            // score / best / retry — sheets often failed to present under smoke.
            if showContinue {
                gameOverOverlay
                    .transition(.opacity)
                    .zIndex(55)
            }
        }
        .onAppear(perform: bootstrap)
        .onDisappear {
            scoreAnimTask?.cancel(); scoreAnimTask = nil
            gestureHintTask?.cancel()
            GameKitService.shared.setPlayDeferral(false)
        }
        .onChange(of: hudScore) { _, newValue in animateScore(to: newValue) }
        .onChange(of: scenePhase) { _, phase in
            // Auto-pause on resign. Becoming active again does NOT unpause.
            // Exception: demo/autoplay/smoke must keep running — simctl recordVideo
            // briefly flips inactive and was freezing the 45s clip on one frame.
            if phase == .inactive || phase == .background {
                if Self.isDemoOrSmokeAutoplay { return }
                enterPause(as: .resign)
            }
        }
        .onChange(of: raccoonMood) { _, _ in
            raccoonBounce = 0.82
            withAnimation(.spring(response: 0.28, dampingFraction: 0.45)) {
                raccoonBounce = 1.0
            }
        }
    }

    /// Full-screen game-over panel — score, best, retry. Overlay (not sheet) so
    /// fit/smoke screenshots and the later Game Center rank hook stay reliable.
    private var gameOverOverlay: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            NeonPanel {
                VStack(spacing: 14) {
                    BundleImage(name: "RaccoonPanic")
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                    Text(isNewBest ? "NEW BEST" : (nearMiss ? "SO CLOSE" : "BIN FULL"))
                        .font(.title2.bold())
                        .foregroundStyle(isNewBest ? NeonTheme.teal : NeonTheme.magenta)
                    Text(ScoreFormat.commas(sheetScore))
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(
                            LinearGradient(colors: [.white, NeonTheme.teal], startPoint: .leading, endPoint: .trailing)
                        )
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.12), value: sheetScore)
                        .accessibilityIdentifier("gameOverScore")
                    Text(gameOverBestSubtitle)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(NeonTheme.muted)
                    Text(reviveHelpText)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(NeonTheme.muted)
                    NeonButton(title: "Play again") {
                        showContinue = false
                        Task { await playAgainNow() }
                    }
                    if !continued {
                        NeonButton(title: reviveButtonTitle, style: .secondary) {
                            Task { await performRevive() }
                        }
                    }
                    NeonButton(title: "Clock out", style: .ghost) {
                        showContinue = false
                        Task { await finalizeOver() }
                    }
                }
            }
            .padding(22)
        }
        .accessibilityLabel("Game over")
    }

    /// Lean top bar: pause · bandit · score · level · ONE current goal.
    /// Bandit sits beside the HUD (not on the board) so the bin keeps full width.
    private var leanHudBar: some View {
        HStack(alignment: .center, spacing: 8) {
            Button {
                AudioService.shared.playSFX("ui")
                enterPause(as: .user)
            } label: {
                Image(systemName: "pause.fill")
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(NeonTheme.teal)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)

            BanditLoopView(mood: raccoonMood, size: 52)
                .scaleEffect(raccoonBounce)
                .accessibilityLabel("The Bandit")

            VStack(alignment: .leading, spacing: 2) {
                Text(ScoreFormat.commas(displayScore))
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("hudScore")
                HStack(spacing: 8) {
                    Text("LVL \(hudLevel)")
                        .font(.caption.weight(.black).monospacedDigit())
                        .foregroundStyle(NeonTheme.magenta)
                    if let goal = orders.first(where: { !$0.done }) ?? orders.first {
                        Text(goal.label)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(goal.done ? NeonTheme.teal : NeonTheme.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }

    private var toastBanner: some View {
        Group {
            if let toastText {
                Text(toastText)
                    .font(.system(.callout, design: .rounded).weight(.black))
                    .foregroundStyle(toastForeground(for: toastText))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Color.black.opacity(0.72))
                    .transition(.opacity)
            }
        }
        .frame(minHeight: toastText == nil ? 0 : 36)
        .animation(.easeOut(duration: 0.2), value: toastText)
    }

    /// Recycle toasts use the matched material color; everything else stays teal/magenta.
    private func toastForeground(for text: String) -> Color {
        let upper = text.uppercased()
        if upper.contains("CHAIN") { return NeonTheme.magenta }
        if upper.contains("METAL") { return Color(red: 0.78, green: 0.80, blue: 0.84) }
        if upper.contains("PLASTIC") { return Color(red: 0.95, green: 0.22, blue: 0.70) }
        if upper.contains("PAPER") { return Color(red: 0.96, green: 0.58, blue: 0.18) }
        if upper.contains("GLASS") { return Color(red: 0.15, green: 0.88, blue: 0.94) }
        return NeonTheme.teal
    }

    private var miniNextHold: some View {
        VStack(spacing: 6) {
            Text("NEXT").font(.system(size: 8, weight: .black)).foregroundStyle(NeonTheme.muted)
            ForEach(Array(preview.prefix(2).enumerated()), id: \.offset) { _, id in
                BundleImage(name: JunkCatalog.textureName(for: id))
                    .scaledToFit()
                    .frame(width: 26, height: 26)
            }
            Text("HOLD").font(.system(size: 8, weight: .black)).foregroundStyle(NeonTheme.muted)
            if let holdItem {
                BundleImage(name: JunkCatalog.textureName(for: holdItem))
                    .scaledToFit()
                    .frame(width: 26, height: 26)
            } else {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(NeonTheme.teal.opacity(0.35), lineWidth: 1)
                    .frame(width: 26, height: 26)
            }
        }
    }

    /// Real player tap-to-place: after a tray piece is selected, every visible cell is tappable.
    private var boardTapToPlaceSeats: some View {
        let placing = selectedTray != nil
        return GeometryReader { geo in
            let cols = max(1, scene.engine.state.board.config.cols)
            let vis = max(1, scene.engine.state.board.config.visibleRows)
            let hid = scene.engine.state.board.config.hiddenRows
            let cs = scene.cellSizePublic()
            let seatW = max(32, cs.width > 1 ? cs.width * 0.95 : geo.size.width / CGFloat(cols))
            let seatH = max(32, cs.height > 1 ? cs.height * 0.95 : geo.size.height / CGFloat(vis) * 0.55)
            ForEach(0..<(cols * vis), id: \.self) { i in
                let col = i % cols
                let visRow = i / cols
                let boardY = hid + (vis - 1 - visRow)
                let pt = scene.scenePointForBoard(x: col, y: boardY)
                let viewX = pt.x > 1 ? pt.x : (CGFloat(col) + 0.5) * (geo.size.width / CGFloat(cols))
                let viewY: CGFloat = {
                    if pt.y > 1 { return geo.size.height - pt.y }
                    // Fallback band: bottom rows map near the dumpster floor.
                    return geo.size.height * (0.22 + CGFloat(visRow) / CGFloat(vis) * 0.55)
                }()
                Button {
                    guard let idx = selectedTray else { return }
                    if scene.engine.state.selectedTrayIndex != idx {
                        _ = scene.selectTraySlot(idx)
                    }
                    scene.previewAtBoard(x: col, y: boardY)
                    _ = scene.placeAtBoard(x: col, y: boardY)
                    selectedTray = scene.engine.state.selectedTrayIndex
                    syncHUD()
                } label: {
                    Color.clear
                        .frame(width: seatW, height: seatH)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .position(x: viewX, y: viewY)
                .accessibilityIdentifier(boardY == scene.engine.state.board.config.rows - 1
                    ? "boardFloor\(col)"
                    : "boardCell_\(col)_\(boardY)")
                .accessibilityLabel("Board column \(col + 1)")
            }
        }
        // Only steal hits while a tray piece is selected — otherwise SpriteKit owns drags.
        .allowsHitTesting(placing)
    }

    private func traySlotView(_ idx: Int) -> some View {
        let piece = traySlots.indices.contains(idx) ? traySlots[idx] : nil
        let selected = selectedTray == idx
        let matColor: Color = {
            guard let id = piece else { return NeonTheme.teal }
            switch JunkCatalog.def(for: id).material {
            case .metal: return Color(red: 0.78, green: 0.82, blue: 0.88)
            case .plastic: return Color(red: 0.95, green: 0.28, blue: 0.72)
            case .glass: return Color(red: 0.20, green: 0.90, blue: 0.95)
            case .paper: return Color(red: 0.96, green: 0.62, blue: 0.22)
            }
        }()
        return ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(selected ? 0.22 : 0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(selected ? matColor : Color.white.opacity(0.18), lineWidth: selected ? 3 : 1)
                )
                .shadow(color: selected ? matColor.opacity(0.75) : .clear, radius: selected ? 12 : 0)
                .frame(width: 78, height: 78)
            if let id = piece {
                BundleImage(name: JunkCatalog.textureName(for: id))
                    .scaledToFit()
                    .frame(width: 54, height: 54)
                    .offset(y: selected ? -10 : 0)
            } else {
                Text("—")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(NeonTheme.muted)
            }
        }
        .offset(y: selected ? -8 : 0)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: selected)
        .contentShape(Rectangle())
        .onTapGesture {
            _ = scene.selectTraySlot(idx)
            selectedTray = idx
            syncHUD()
            AudioService.shared.playSFX("ui")
        }
        .gesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .global)
                .onChanged { value in
                    if scene.engine.state.selectedTrayIndex != idx {
                        _ = scene.selectTraySlot(idx)
                        selectedTray = idx
                        syncHUD()
                    }
                    guard boardFrameGlobal.width > 10 else { return }
                    let local = CGPoint(
                        x: value.location.x - boardFrameGlobal.minX,
                        y: value.location.y - boardFrameGlobal.minY
                    )
                    // SpriteKit scene is y-up; SwiftUI global is y-down.
                    let scenePt = CGPoint(x: local.x, y: boardFrameGlobal.height - local.y)
                    if let cell = scene.boardCell(at: scenePt) {
                        scene.previewAtBoard(x: cell.x, y: cell.y)
                    }
                }
                .onEnded { value in
                    guard boardFrameGlobal.width > 10 else { return }
                    let local = CGPoint(
                        x: value.location.x - boardFrameGlobal.minX,
                        y: value.location.y - boardFrameGlobal.minY
                    )
                    let scenePt = CGPoint(x: local.x, y: boardFrameGlobal.height - local.y)
                    if let cell = scene.boardCell(at: scenePt) {
                        _ = scene.placeAtBoard(x: cell.x, y: cell.y)
                    }
                    syncHUD()
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tray piece \(idx + 1)")
        .accessibilityIdentifier("traySlot\(idx)")
        .accessibilityAddTraits(.isButton)
    }

    private var turnBasedTray: some View {
        VStack(spacing: 10) {
            if let teachHint, !teachHint.isEmpty {
                Text(teachHint)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NeonTheme.teal)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("teachHint")
            }
            HStack {
                Text("Moves \(movesLeft)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(NeonTheme.muted)
                    .accessibilityIdentifier("movesLeft")
                Spacer()
                Text("TRAY")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(NeonTheme.muted)
            }
            HStack(spacing: 16) {
                ForEach(0..<3, id: \.self) { idx in
                    traySlotView(idx)
                }
            }
            .frame(maxWidth: .infinity)
            HStack(spacing: 8) {
                boosterChip("Magnet", count: boostMagnet) {
                    if let mat = scene.engine.state.active?.material
                        ?? scene.engine.state.tray.compactMap({ $0 }).first.map({ JunkCatalog.def(for: $0).material }) {
                        _ = scene.engine.useMagnet(material: mat)
                        scene.flushEngineEvents()
                        scene.render(immediate: false)
                        syncHUD()
                    }
                }
                boosterChip("Crush", count: boostCrusher) {
                    let rows = scene.engine.state.board.config.rows
                    outer: for y in (0..<rows).reversed() {
                        for x in 0..<scene.engine.state.board.config.cols {
                            if scene.engine.useCrusher(x: x, y: y) {
                                scene.flushEngineEvents()
                                scene.render(immediate: false)
                                break outer
                            }
                        }
                    }
                    syncHUD()
                }
                boosterChip("SLAM", count: boostSlam) {
                    _ = scene.engine.useSlamBooster()
                    scene.flushEngineEvents()
                    scene.render(immediate: false)
                    AudioService.shared.playSFX("crush")
                    syncHUD()
                }
                .accessibilityLabel("Slam press")
                boosterChip("Shuffle", count: boostShuffle) {
                    _ = scene.engine.useShuffle()
                    scene.render(immediate: true)
                    syncHUD()
                }
            }
        }
    }

    private func boosterChip(_ title: String, count: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("\(title) \(count)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(count > 0 ? Color.black : NeonTheme.muted)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(count > 0 ? NeonTheme.teal : Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(count <= 0)
    }

    private var pauseOverlay: some View {
        ZStack {
            Color.black.opacity(0.78).ignoresSafeArea()
            VStack(spacing: 14) {
                Text("PAUSED")
                    .font(.title.weight(.black))
                    .foregroundStyle(NeonTheme.teal)
                Text("Match 4+ of the same material. Fill PRESS, then SLAM.")
                    .font(.caption)
                    .foregroundStyle(NeonTheme.muted)
                    .multilineTextAlignment(.center)
                // Extra goals live here — not on the live HUD.
                ForEach(orders) { order in
                    HStack {
                        Text(order.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(order.done ? NeonTheme.teal : .white)
                        Spacer()
                        Text("\(order.progress)/\(order.target)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(NeonTheme.muted)
                    }
                }
                NeonButton(title: "Resume") {
                    resumePause()
                }
                NeonButton(title: "Quit to title", style: .ghost) {
                    resumePause()
                    AudioService.shared.playMusic("menu_loop")
                    screen = .title
                }
            }
            .padding(22)
            .background(NeonTheme.panel.opacity(0.96))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 28)
        }
        .accessibilityLabel("Paused")
    }

    private func enterPause(as reason: PauseGate.Reason) {
        guard pauseGate.pause(as: reason) else { return }
        scene.isPaused = true
    }

    private func resumePause() {
        guard pauseGate.resume() else { return }
        scene.isPaused = false
    }

    private var classicPad: some View {
        let das = scene.feel.dasDelaySec
        let arr = scene.feel.arrIntervalSec
        let softR = scene.feel.softRepeatSec
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                RepeatPadButton(
                    title: "◀",
                    accessibility: "Move left",
                    dasDelay: das,
                    repeatInterval: arr
                ) {
                    scene.moveLeft()
                }
                // Rotate is a single tap — light haptic + click, no hold-repeat.
                RepeatPadButton(title: "↻", accessibility: "Rotate", dasDelay: 99, repeatInterval: 99, fireOnce: true) {
                    scene.rotate()
                    AudioService.shared.playSFX("ui")
                    HapticsService.shared.tap()
                }
                RepeatPadButton(
                    title: "▶",
                    accessibility: "Move right",
                    dasDelay: das,
                    repeatInterval: arr
                ) {
                    scene.moveRight()
                }
                RepeatPadButton(title: "HOLD", accessibility: "Hold piece", dasDelay: 99, repeatInterval: 99, fireOnce: true) {
                    scene.stash()
                    AudioService.shared.playSFX("ui")
                    HapticsService.shared.tap()
                }
            }
            HStack(spacing: 10) {
                RepeatPadButton(
                    title: "SOFT",
                    accessibility: "Soft drop",
                    dasDelay: 0.04,
                    repeatInterval: softR
                ) {
                    scene.soft()
                }
                RepeatPadButton(
                    title: "DROP",
                    accessibility: "Hard drop",
                    emphasis: true,
                    dasDelay: 99,
                    repeatInterval: 99,
                    fireOnce: true
                ) {
                    // Juice lives on `.locked(hard:)` — don't double-fire SFX/haptics here.
                    scene.hard()
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Touch controls")
    }

    private func dismissHowTo() {
        profile.tutorialDone = true
        // Gesture-first by default; Settings → Buttons for the classic pad.
        profile.classicButtons = false
        profile.persist()
        showHowTo = false
        scene.isPaused = false
        AudioService.shared.playSFX("ui")
        scene.startShiftLevel(1)
        syncHUD()
        displayScore = scene.engine.state.score
        // One instruction: teach hint lives under the tray; skip the conflicting top tip.
        if scene.engine.state.teachHint == nil || scene.engine.state.teachHint?.isEmpty == true {
            showToast("Tap a tray piece, then tap the board")
            presentGestureHint()
        } else {
            showToast(scene.engine.state.teachHint!)
        }
    }

    private func presentGestureHint() {
        // Don't fight the level-1 teach line under the tray.
        if let tip = scene.engine.state.teachHint, !tip.isEmpty { return }
        showGestureHint = true
        gestureHintTask?.cancel()
        gestureHintTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            showGestureHint = false
        }
    }

    private func openLevelMapAfterWin() {
        let cleared = max(1, scene.engine.state.levelId)
        let next = min(20, cleared + 1)
        profile.shiftProgress = max(profile.shiftProgress, cleared)
        profile.persist()
        UserDefaults.standard.set("\(next)", forKey: "trashStack.shiftLevel")
        showLevelWin = false
        pendingWinStars = nil
        screen = .shiftMap
    }

    /// Present LEVEL CLEAR only after on-board CHAIN has finished (or a safe fallback beat).
    private func scheduleLevelWinOverlay(stars: Int) {
        winPresentTask?.cancel()
        winPresentTask = Task { @MainActor in
            // Fly (~0.4s) + CHAIN hold (~0.9s). Combo callback may fire earlier.
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled, pendingWinStars != nil, scene.engine.state.levelWon else { return }
            presentLevelWinOverlay(stars: stars)
        }
    }

    private func presentLevelWinOverlay(stars: Int) {
        guard !showLevelWin else { return }
        pendingWinStars = nil
        winPresentTask?.cancel()
        winPresentTask = nil
        showLevelWin = true
        AudioService.shared.playSFX("levelup")
        showToast(stars == 1 ? "Level clear · 1 star" : "Level clear · \(stars) stars")
    }

    private func syncHUD() {
        hudScore = scene.engine.state.score
        hudLevel = scene.engine.state.levelId > 0 ? scene.engine.state.levelId : scene.engine.state.level
        pressMeter = scene.engine.state.pressMeter
        pressMax = scene.engine.state.pressMeterMax
        snatchReady = scene.engine.state.snatchAvailable
        orders = scene.engine.state.orders
        raccoonMood = scene.raccoonMood
        preview = scene.engine.peekNext(2)
        holdItem = scene.engine.state.hold
        traySlots = scene.engine.state.tray
        movesLeft = scene.engine.state.movesLeft
        teachHint = scene.engine.state.teachHint
        starsEarned = scene.engine.state.starsEarned
        boostMagnet = scene.engine.state.boosters.magnet
        boostCrusher = scene.engine.state.boosters.crusher
        boostSlam = scene.engine.state.boosters.slam
        boostShuffle = scene.engine.state.boosters.shuffle
        selectedTray = scene.engine.state.selectedTrayIndex
        // Win overlay is scheduled after CHAIN finishes — never snap it on mid-combo.
        let wasNear = nearMiss
        nearMiss = scene.engine.isNearOverflow(threshold: scene.feel.nearMissRows)
        if nearMiss, !wasNear {
            // Near-miss tension bed: low, uneasy loop cue (no separate asset yet).
            AudioService.shared.playMusic("game_loop")
            AudioService.shared.playSFX("ui", pitch: 0.55)
            AudioService.shared.playSFX("lock", pitch: 0.45)
            HapticsService.shared.tap()
        } else if !nearMiss, wasNear {
            AudioService.shared.playMusic("game_loop")
        }
    }

    private func showToast(_ text: String) {
        // Latest-only: drop stale queued toasts; never more than one pending.
        toastQueue = [text]
        // If something is already showing, replace it immediately with the newest.
        toastTask?.cancel()
        toastTask = nil
        toastText = text
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            toastText = nil
            toastQueue.removeAll()
            toastTask = nil
        }
    }

    private func animateScore(to target: Int) {
        scoreAnimTask?.cancel()
        let start = displayScore
        let delta = target - start
        guard delta != 0 else { return }
        let steps = min(24, max(8, abs(delta) / 40))
        scoreAnimTask = Task { @MainActor in
            for step in 1...steps {
                try? await Task.sleep(nanoseconds: 30_000_000)
                if Task.isCancelled { return }
                let t = Double(step) / Double(steps)
                let eased = 1 - pow(1 - t, 3)
                displayScore = start + Int(Double(delta) * eased)
            }
            displayScore = target
        }
    }

    private func bootstrap() {
        scene.scaleMode = .resizeFill
        scene.isPaused = false
        scene.configureForProMotion(false)
        LaunchTiming.markPlayTap()
        AudioService.shared.applyPersistedMute()
        // Quiet GC banners / access point while the run is live.
        GameKitService.shared.setPlayDeferral(true)
        GameKitService.shared.configureAccessPoint(show: false)
        // Demo/shot paths skip the ident — still warm textures before first board paint.
        AssetPreloader.preloadDuringIdent()
        // First launch: how-to overlay. Smoke/shot paths skip. Buttons off by default.
        let shotPeek = UserDefaults.standard.string(forKey: "trashStack.shotActive")
            ?? PlayerProfile.shotArgument()
        let isShot = shotPeek != nil && !(shotPeek?.isEmpty ?? true)
        if !isShot {
            profile.classicButtons = false
        }
        if !profile.tutorialDone, !isShot {
            showHowTo = true
            scene.isPaused = true
        }
        // Gesture tip deferred until after startShiftLevel / syncHUD so L1 teachHint wins.
        let shot = shotPeek
        let auto = shot == "demo" || shot == "autoplay" || ProcessInfo.processInfo.arguments.contains("-autoplay")
        scene.autoplay = auto
        let modeShot: String? = {
            if let shot { return shot }
            if playMode == .daily { return "daily" }
            return nil
        }()
        // Wire stamp callback before applyShot / SKView present so cold launches cannot miss it.
        scene.onFirstGameFrame = {
            Task { @MainActor in
                LaunchTiming.markFirstGameFrame()
                if auto {
                    let playScene = scene
                    playScene.autoplay = true
                    // Live-run near-miss / GO only — never swap score/level mid-demo.
                    playScene.startDemoChoreography {
                        Task { @MainActor in
                            // Score already synced via onGameOver from the live top-out.
                            hudScore = playScene.engine.state.score
                            displayScore = playScene.engine.state.score
                            raccoonMood = .panic
                            showContinue = true
                            try? await Task.sleep(nanoseconds: 2_200_000_000)
                            showContinue = false
                            continued = true
                            playScene.revive()
                            if !AudioService.shared.isMuted {
                                AudioService.shared.playSFX("levelup")
                            }
                        }
                    }
                }
                if !AudioService.shared.isMuted {
                    AudioService.shared.playMusic("game_loop")
                }
                syncHUD()
                displayScore = scene.engine.state.score
            }
        }
        // Apply board content immediately so the first SpriteKit paint is a filled bin, not gray empty.
        if let modeShot, ["game", "gameplay", "compactor", "press", "recycle", "revive", "demo", "autoplay", "daily"].contains(modeShot) {
            scene.applyShot(modeShot)
            if modeShot == "revive" {
                scene.autoplay = false
                raccoonMood = .panic
                nearMiss = true
                // Smoke-only staged board — lock overlay score to that board, not a stale HUD.
                captureGameOverScore(scene.engine.state.score)
                lastState = scene.engine.state
                syncHUD()
                // Show the score/best/retry overlay immediately. A 0.2s defer left CI
                // screenshots on the bare topped-out board ("BIN OVERFLOW" only).
                showContinue = true
                // Re-assert after the first SpriteKit present — Pro CI sometimes painted
                // the topped-out board for one frame before the sheet stuck off-screen.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    captureGameOverScore(scene.engine.state.score)
                    showContinue = true
                    syncHUD()
                }
            }
        } else if playMode == .daily {
            scene.startDailySortPuzzle()
        } else if playMode == .shift {
            let raw = UserDefaults.standard.string(forKey: "trashStack.shiftLevel") ?? "1"
            let id = Int(raw) ?? raw.split(separator: "-").last.flatMap { Int($0) } ?? 1
            scene.startShiftLevel(max(1, id))
        } else if UserDefaults.standard.bool(forKey: "tt.weeklyRun") {
            scene.reset(seed: WeeklyTournament.seed())
            UserDefaults.standard.set(false, forKey: "tt.weeklyRun")
        } else {
            // Fresh puzzle — Level 1 teaches drag-and-place.
            scene.reset()
        }
        syncHUD()
        if !showHowTo, !profile.classicButtons, !isShot {
            presentGestureHint()
        }
        scene.onGameOver = { state in
            Task { @MainActor in
                // Lock the live top-out score before any sheet / HUD race.
                captureGameOverScore(state.score)
                syncHUD()
                raccoonMood = .panic
                await handleGameOver(state)
            }
        }
        scene.onToast = { text in
            Task { @MainActor in
                showToast(text)
            }
        }
        scene.onPieceSnap = {
            Task { @MainActor in
                AudioService.shared.playSFX("ui", pitch: 1.25)
                HapticsService.shared.tap()
            }
        }
        scene.onMood = { mood in
            Task { @MainActor in
                raccoonMood = mood
            }
        }
        scene.onComboFinished = {
            Task { @MainActor in
                guard let stars = pendingWinStars else { return }
                presentLevelWinOverlay(stars: stars)
            }
        }
        scene.onEvents = { [weak scene] events in
            Task { @MainActor in
                guard let scene else { return }
                syncHUD()
                for e in events {
                    switch e {
                    case .locked(let hard):
                        if hard {
                            AudioService.shared.playSFX("crush", pitch: 0.88)
                            AudioService.shared.playSFX("lock", pitch: 1.2)
                            HapticsService.shared.clear()
                        } else {
                            // Soft land thud — crisp enough to feel the bin, softer than DROP.
                            AudioService.shared.playSFX("lock", pitch: 0.78)
                            HapticsService.shared.lock()
                        }
                    case .recycled(_, let cells, _, _, _, _):
                        let combo = max(1, scene.engine.state.combo)
                        let pitch = 1.0 + Double(combo) * 0.12
                        AudioService.shared.playSFX("recycle", pitch: pitch)
                        AudioService.shared.playSFX("crush", pitch: 1.15)
                        if combo >= 2 {
                            AudioService.shared.playSFX("combo", pitch: min(1.9, pitch + 0.08))
                        }
                        if combo >= 4 {
                            AudioService.shared.playSFX("levelup", pitch: 1.15)
                            HapticsService.shared.clear()
                        } else if cells >= 8 {
                            HapticsService.shared.clear()
                        } else {
                            HapticsService.shared.recycle()
                        }
                        Task { await GameKitService.shared.reportAchievement(AchievementID.firstRecycle) }
                        if scene.engine.state.combo >= 5 {
                            Task { await GameKitService.shared.reportAchievement(AchievementID.chainFive) }
                        }
                    case .pressed:
                        AudioService.shared.playSFX("crush")
                        HapticsService.shared.clear()
                        Task { await GameKitService.shared.reportAchievement(AchievementID.pressSlam) }
                    case .levelWon(let stars):
                        starsEarned = stars
                        pendingWinStars = stars
                        // Wait for fly-to-goal + CHAIN banner before LEVEL CLEAR covers the board.
                        scheduleLevelWinOverlay(stars: stars)
                    case .placed:
                        AudioService.shared.playSFX("lock", pitch: 0.9)
                        HapticsService.shared.lock()
                    case .shuffled:
                        showToast("Tray shuffled")
                    case .crushed:
                        AudioService.shared.playSFX("crush", pitch: 1.1)
                    case .orderCompleted(let order):
                        AudioService.shared.playSFX("levelup")
                        completedOrderFlash = order.id
                        rewardFly = "+XP · +gems"
                        showToast("Order done")
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 1_200_000_000)
                            if completedOrderFlash == order.id { completedOrderFlash = nil }
                            rewardFly = nil
                        }
                    case .snatchUsed:
                        AudioService.shared.playSFX("magnet")
                        Task { await GameKitService.shared.reportAchievement(AchievementID.snatchUsed) }
                    case .leveledUp(let lvl):
                        AudioService.shared.playSFX("levelup")
                        let twist = LevelTwist.active(at: lvl)
                        showToast(twist.toastTitle)
                    case .spawned:
                        syncHUD()
                    default: break
                    }
                }
                UserDefaults.standard.set(scene.measuredFPS, forKey: "trashStack.measuredFPS")
            }
        }
        syncHUD()
        displayScore = scene.engine.state.score
        AudioService.shared.playMusic("game_loop")
    }

    private var gameOverBestSubtitle: String {
        let best = max(overBestBefore, overScore)
        if isNewBest {
            if overBestBefore > 0 {
                return "Best \(ScoreFormat.commas(overScore)) · beat \(ScoreFormat.commas(overBestBefore))"
            }
            return "Best \(ScoreFormat.commas(overScore))"
        }
        var line = "Best \(ScoreFormat.commas(best))"
        if profile.dailyStreak > 0 {
            line += " · streak \(profile.dailyStreak)d"
        }
        return line
    }

    private var reviveAdsAvailable: Bool { AdsService.shared.rewardedAdsConfigured }

    private var reviveButtonTitle: String {
        reviveAdsAvailable ? "Revive (ad)" : "Revive"
    }

    private var reviveHelpText: String {
        if continued { return "You've already revived this run." }
        if reviveAdsAvailable {
            return nearMiss
                ? "One revive (opt-in ad) or jump straight back in."
                : "Revive once with an opt-in ad, or play again now."
        }
        return "One free revive this run, or play again now."
    }

    @MainActor
    private func performRevive() async {
        if reviveAdsAvailable {
            // ATT/UMP only on opt-in rewarded tap — never stacked on the loss sheet itself.
            await AdsBootstrap.startAfterFirstWinIfNeeded()
            let ok = await AdsService.shared.showRewarded(placement: "revive")
            showContinue = false
            if ok {
                continued = true
                scene.revive()
                AudioService.shared.playMusic("game_loop")
            } else {
                await finalizeOver()
            }
            return
        }
        // No ad network configured — free once-per-run revive (never a dead button).
        showContinue = false
        continued = true
        scene.revive()
        AudioService.shared.playMusic("game_loop")
    }

    @MainActor
    private func captureGameOverScore(_ score: Int) {
        // Idempotent: scene used to re-fire onGameOver every tick and kept resetting
        // sheetScore to 0 mid-animation (CI screenshots showed "NEW BEST / 0").
        if overScore > 0, score == overScore, sheetScore == score { return }
        overScore = score
        hudScore = score
        displayScore = score
        overBestBefore = max(profile.highScore, profile.endlessHighScore)
        isNewBest = score > overBestBefore
        // Show the true final score immediately — screenshots and testers must never see 0.
        sheetScoreAnimTask?.cancel()
        sheetScore = score
        if isNewBest {
            AudioService.shared.playSFX("levelup", pitch: 1.2)
            HapticsService.shared.clear()
        }
    }

    @MainActor
    private func handleGameOver(_ state: GameState) async {
        lastState = state
        // Prefer the locked top-out score if something mutated state afterward.
        if overScore == 0 { captureGameOverScore(state.score) }
        // Calm moment — flush queued achievements / allow banners again.
        GameKitService.shared.setPlayDeferral(false)
        if !continued {
            showContinue = true
            return
        }
        await finalizeOver()
    }

    /// Persist rewards and jump into a fresh run — no title hop, no interstitial wait.
    @MainActor
    private func playAgainNow() async {
        _ = await bankRunRewards(submitScores: true)
        continued = false
        lastState = nil
        overScore = 0
        sheetScore = 0
        isNewBest = false
        raccoonMood = .idle
        nearMiss = false
        GameKitService.shared.setPlayDeferral(true)
        GameKitService.shared.configureAccessPoint(show: false)
        if playMode == .daily {
            scene.applyShot("daily")
        } else {
            scene.reset()
        }
        syncHUD()
        displayScore = 0
        hudScore = 0
        AudioService.shared.playSFX("ui")
        AudioService.shared.playMusic("game_loop")
    }

    @MainActor
    private func bankRunRewards(submitScores: Bool) async -> GameState? {
        guard let state = lastState ?? Optional(scene.engine.state) else { return nil }
        let scored = overScore > 0 ? overScore : state.score
        profile.addScrap(state.runScrap)
        profile.battlePassXP += state.lines * 2 + 5
        for order in state.orders where order.done {
            profile.addGems(2)
            profile.battlePassXP += 15
        }
        if scored > profile.highScore {
            profile.highScore = scored
        }
        if playMode == .endless {
            if scored > profile.endlessHighScore {
                profile.endlessHighScore = scored
            }
            if submitScores {
                await GameKitService.shared.submitScore(scored, leaderboardID: TrashTalkRules.leaderboardAllTime)
                await GameKitService.shared.submitWeeklyScore(scored)
                if scored >= 10_000 {
                    await GameKitService.shared.reportAchievement(AchievementID.allTime10k)
                }
                if scored >= 50_000 {
                    await GameKitService.shared.reportAchievement(AchievementID.allTime50k)
                }
            }
        }
        if playMode == .shift, state.orders.allSatisfy(\.done) {
            profile.shiftProgress = max(profile.shiftProgress, profile.shiftProgress + 1)
        }
        if scored > 0 && !profile.firstWin {
            profile.firstWin = true
        }
        profile.persist()
        return state
    }

    @MainActor
    private func finalizeOver() async {
        guard let state = await bankRunRewards(submitScores: true) else { return }
        let scored = overScore > 0 ? overScore : state.score
        if playMode == .daily {
            let stars = state.orders.filter(\.done).count
            let card = DailyDumpster.shareCard(
                dayKey: DailyDumpster.dayKey(),
                score: scored,
                stars: min(3, max(1, stars)),
                materialGrid: scene.engine.materialShareGrid()
            )
            profile.markDailyComplete(score: scored)
            await GameKitService.shared.submitScore(scored, leaderboardID: "trashstack_daily")
            await GameKitService.shared.reportAchievement(AchievementID.dailyClear)
            if profile.dailyStreak >= 7 {
                await GameKitService.shared.reportAchievement(AchievementID.streakSeven)
            }
            profile.persist()
            continued = false
            overScore = 0
            AudioService.shared.playMusic("menu_loop")
            onDailyFinished?(scored, card)
            return
        }
        // Never fire ATT/UMP/notification prompts on game-over. Notifications: win / streak / settings (2nd session).
        let streak = profile.registerDailyActivity()
        profile.persist()
        await AdsService.shared.maybeShowInterstitial()
        continued = false
        overScore = 0
        AudioService.shared.playMusic("menu_loop")
        if streak.isNew, streak.scrap > 0 {
            if profile.mayPromptNotifications {
                showNotifPrompt = true
            }
            onStreakReward?(streak.streak, streak.scrap, streak.gems)
        } else {
            screen = .title
        }
    }
}

/// Classic pad button with DAS/ARR hold-repeat (or single-fire for rotate/DROP/HOLD).
struct RepeatPadButton: View {
    let title: String
    let accessibility: String
    var emphasis: Bool = false
    var dasDelay: Double = 0.16
    var repeatInterval: Double = 0.045
    /// When true, only the initial press fires (no hold repeat).
    var fireOnce: Bool = false
    let action: () -> Void

    @State private var pressed = false
    @State private var repeatTask: Task<Void, Never>?

    var body: some View {
        Text(title)
            .font(.system(size: emphasis ? 20 : 18, weight: .black, design: .rounded))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .foregroundStyle(emphasis ? .black : .white)
            .background {
                if emphasis {
                    LinearGradient(colors: [NeonTheme.teal, NeonTheme.magenta], startPoint: .leading, endPoint: .trailing)
                } else {
                    NeonTheme.panel
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(emphasis ? Color.clear : NeonTheme.teal.opacity(0.55), lineWidth: 1.5)
            )
            .scaleEffect(pressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.08), value: pressed)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressed else { return }
                        pressed = true
                        action()
                        guard !fireOnce else { return }
                        repeatTask?.cancel()
                        let delay = dasDelay
                        let interval = repeatInterval
                        repeatTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: UInt64(max(0.01, delay) * 1_000_000_000))
                            while !Task.isCancelled {
                                action()
                                try? await Task.sleep(nanoseconds: UInt64(max(0.02, interval) * 1_000_000_000))
                            }
                        }
                    }
                    .onEnded { _ in
                        pressed = false
                        repeatTask?.cancel()
                        repeatTask = nil
                    }
            )
            .onDisappear {
                // Lost touch / view teardown must never leave SOFT latched.
                pressed = false
                repeatTask?.cancel()
                repeatTask = nil
            }
            .accessibilityLabel(accessibility)
            .accessibilityAddTraits(.isButton)
    }
}

private struct BoardGlobalFrameKey: PreferenceKey {
    // PreferenceKey requires `static var`; mark unsafe for Swift 6 concurrency.
    nonisolated(unsafe) static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

/// Short first-launch card — dismisses into live play with the classic pad visible underneath.
struct HowToPlayOverlay: View {
    var onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 18) {
                Text("HOW TO PLAY")
                    .font(.system(.title2, design: .rounded).weight(.black))
                    .foregroundStyle(NeonTheme.teal)
                VStack(alignment: .leading, spacing: 12) {
                    howRow("TRAY", "Tap any of the 3 pieces")
                    howRow("PLACE", "Tap a board spot — or drag it there")
                    howRow("GHOST", "Preview fits · red means it won’t fit")
                    howRow("4+", "Match 4 of the same material to recycle")
                    howRow("CHAIN", "Clears can settle into more clears")
                    howRow("SLAM", "Earn it, then crush the bottom 2 rows")
                }
                .padding(.horizontal, 8)
                Text("Want buttons? Settings → Buttons")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(NeonTheme.muted)
                NeonButton(title: "GOT IT — PLAY") {
                    onDismiss()
                }
                .padding(.horizontal, 12)
                Button("Skip") { onDismiss() }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NeonTheme.muted)
            }
            .padding(22)
            .background(NeonTheme.panel.opacity(0.96))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(NeonTheme.teal.opacity(0.55), lineWidth: 1.5)
            )
            .padding(.horizontal, 28)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("How to play")
    }

    private func howRow(_ badge: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Text(badge)
                .font(.system(.headline, design: .rounded).weight(.black))
                .foregroundStyle(.black)
                .frame(width: 56, height: 36)
                .background(NeonTheme.teal)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
