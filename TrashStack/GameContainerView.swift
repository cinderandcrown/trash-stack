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
    @State private var scene = CompactorScene(size: CGSize(width: 390, height: 780))
    @State private var showContinue = false
    @State private var lastState: GameState?
    @State private var continued = false
    @State private var hudScore = 0
    @State private var displayScore = 0
    @State private var hudLevel = 1
    @State private var raccoonMood: CompactorScene.RaccoonMood = .idle
    @State private var showPause = false
    @State private var scoreAnimTask: Task<Void, Never>?
    @State private var sheetScoreAnimTask: Task<Void, Never>?
    @State private var pressMeter = 0
    @State private var pressMax = 8
    @State private var snatchReady = true
    @State private var orders: [OrderTicket] = []
    @State private var preview: [JunkID] = []
    @State private var holdItem: JunkID? = nil
    @State private var nearMiss = false
    @State private var toastText: String? = nil
    @State private var toastQueue: [String] = []
    @State private var toastTask: Task<Void, Never>? = nil
    @State private var snatchPressed = false
    @State private var completedOrderFlash: String? = nil
    @State private var rewardFly: String? = nil
    /// Locked at top-out — never a stale HUD or smoke-staged value.
    @State private var overScore = 0
    @State private var sheetScore = 0
    @State private var overBestBefore = 0
    @State private var isNewBest = false

    var body: some View {
        VStack(spacing: 0) {
            hudBar
            orderStrip
            toastBanner
            previewHoldBar

            SpriteView(scene: scene)
                .background(Color(red: 0.05, green: 0.06, blue: 0.10))
                .ignoresSafeArea(edges: .horizontal)
                .layoutPriority(1)
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

            if profile.classicButtons {
                classicPad
            } else {
                gestureHint
            }

            HStack(spacing: 12) {
                let pressReady = pressMeter >= pressMax
                Button {
                    scene.slamPress()
                    AudioService.shared.playSFX("crush")
                    HapticsService.shared.clear()
                    syncHUD()
                } label: {
                    VStack(spacing: 4) {
                        Text(pressReady ? "SLAM!" : "PRESS")
                            .font(.caption.weight(.black))
                        ProgressView(value: Double(pressMeter), total: Double(max(1, pressMax)))
                            .tint(pressReady ? NeonTheme.gold : NeonTheme.teal)
                        Text(pressReady ? "TAP TO CRUSH" : "\(pressMeter)/\(pressMax)")
                            .font(.caption2.monospacedDigit().weight(.bold))
                    }
                    .foregroundStyle(pressReady ? .black : .white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, pressReady ? 14 : 10)
                    .frame(maxWidth: .infinity)
                    .background(
                        LinearGradient(
                            colors: pressReady
                                ? [NeonTheme.gold, NeonTheme.magenta]
                                : [NeonTheme.panel, NeonTheme.panel],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: pressReady ? NeonTheme.magenta.opacity(0.55) : .clear, radius: 12, y: 0)
                    .scaleEffect(pressReady ? 1.04 : 1)
                    .animation(.easeOut(duration: 0.18), value: pressReady)
                }
                .buttonStyle(.plain)
                .disabled(!pressReady)
                .accessibilityLabel(pressReady ? "Slam the press" : "Press meter \(pressMeter) of \(pressMax)")

                // Snatch stays available but smaller when SLAM is the star.
                Button {
                    snatchPressed = true
                    scene.magnet()
                    AudioService.shared.playSFX("magnet")
                    HapticsService.shared.tap()
                    syncHUD()
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 180_000_000)
                        snatchPressed = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        BundleImage(name: raccoonAsset).frame(width: pressReady ? 22 : 28, height: pressReady ? 22 : 28)
                        Text(snatchReady ? "SNATCH" : "USED")
                            .font(.caption.weight(.black))
                            .foregroundStyle(pressReady ? .white : .black)
                    }
                    .padding(.horizontal, pressReady ? 12 : 16)
                    .padding(.vertical, pressReady ? 12 : 14)
                    .background(
                        LinearGradient(
                            colors: snatchReady
                                ? (pressReady
                                   ? [NeonTheme.panel, NeonTheme.panel]
                                   : [NeonTheme.teal, NeonTheme.magenta])
                                : [NeonTheme.panel, NeonTheme.panel],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(pressReady && snatchReady ? NeonTheme.teal.opacity(0.5) : .clear, lineWidth: 1)
                    )
                    .opacity(snatchReady ? 1 : 0.55)
                    .scaleEffect(snatchPressed ? 0.92 : 1)
                    .animation(.easeOut(duration: 0.12), value: snatchPressed)
                }
                .buttonStyle(.plain)
                .disabled(!snatchReady)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
        }
        // Quiet chrome — board owns the color; HUD stays dim and in safe areas.
        .background(NeonTheme.playChrome.ignoresSafeArea())
        .safeAreaPadding(.top, 4)
        .safeAreaPadding(.bottom, 6)
        .onAppear(perform: bootstrap)
        .onDisappear { scoreAnimTask?.cancel(); scoreAnimTask = nil }
        .onChange(of: hudScore) { _, newValue in animateScore(to: newValue) }
        .sheet(isPresented: $showPause) {
            ZStack {
                NeonTheme.bgBottom.ignoresSafeArea()
                NeonPanel {
                    VStack(spacing: 16) {
                        Text("PAUSED").font(.title2.bold()).foregroundStyle(NeonTheme.teal)
                        Text("Match 4+ of the same material to recycle. Fill the PRESS meter, then slam.")
                            .font(.caption)
                            .foregroundStyle(NeonTheme.muted)
                            .multilineTextAlignment(.center)
                        NeonButton(title: "Resume") { showPause = false }
                        NeonButton(title: "Quit to title", style: .ghost) {
                            showPause = false
                            AudioService.shared.playMusic("menu_loop")
                            screen = .title
                        }
                    }
                }
                .padding()
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showContinue) {
            ZStack {
                NeonTheme.bgBottom.ignoresSafeArea()
                NeonPanel {
                    VStack(spacing: 14) {
                        BundleImage(name: "RaccoonPanic")
                            .scaledToFit()
                            .frame(width: 100, height: 100)
                        Text(isNewBest ? "NEW BEST" : (nearMiss ? "SO CLOSE" : "BIN FULL"))
                            .font(.title2.bold())
                            .foregroundStyle(isNewBest ? NeonTheme.teal : NeonTheme.magenta)
                        Text("\(sheetScore)")
                            .font(.system(size: 44, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(
                                LinearGradient(colors: [.white, NeonTheme.teal], startPoint: .leading, endPoint: .trailing)
                            )
                            .contentTransition(.numericText())
                            .animation(.easeOut(duration: 0.12), value: sheetScore)
                        Text(isNewBest
                             ? "Best \(overScore) · you beat \(overBestBefore)"
                             : "Best \(max(overBestBefore, overScore))"
                               + (profile.dailyStreak > 0 ? " · streak \(profile.dailyStreak)d" : ""))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(NeonTheme.muted)
                        Text(nearMiss
                             ? "One revive (opt-in ad) or jump straight back in."
                             : "Revive once with an opt-in ad, or play again now.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(NeonTheme.muted)
                        NeonButton(title: "Play again") {
                            showContinue = false
                            Task { await playAgainNow() }
                        }
                        NeonButton(title: "Revive (ad)", style: .secondary) {
                            Task {
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
                            }
                        }
                        NeonButton(title: "Clock out", style: .ghost) {
                            showContinue = false
                            Task { await finalizeOver() }
                        }
                    }
                }
                .padding()
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var hudBar: some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                AudioService.shared.playSFX("ui")
                showPause = true
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(
                                    LinearGradient(colors: [NeonTheme.teal, NeonTheme.magenta], startPoint: .topLeading, endPoint: .bottomTrailing),
                                    lineWidth: 1.4
                                )
                        )
                    Image(systemName: "pause.fill")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(NeonTheme.teal)
                }
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)

            BundleImage(name: raccoonAsset)
                .scaledToFit()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(NeonTheme.magenta.opacity(0.7), lineWidth: 1.2)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("\(displayScore)")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(
                        LinearGradient(colors: [.white, NeonTheme.teal], startPoint: .leading, endPoint: .trailing)
                    )
                    .shadow(color: NeonTheme.teal.opacity(0.55), radius: 6, y: 0)
                    .contentTransition(.numericText())
                Text("LVL \(hudLevel)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(NeonTheme.magenta)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 4) {
                CurrencyChip(kind: .scrap, value: profile.scrap)
                if profile.highScore > 0 {
                    Text("HI \(profile.highScore)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(NeonTheme.muted)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private var orderStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(orders) { order in
                    HStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(order.label)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(order.done ? NeonTheme.teal : .white)
                                .lineLimit(1)
                            ProgressView(value: Double(min(order.progress, order.target)), total: Double(max(1, order.target)))
                                .tint(order.done ? NeonTheme.teal : NeonTheme.magenta)
                        }
                        if order.done || completedOrderFlash == order.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(NeonTheme.teal)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(order.done ? 0.12 : 0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(completedOrderFlash == order.id ? NeonTheme.teal : .clear, lineWidth: 1.5)
                    )
                }
                if let rewardFly {
                    Text(rewardFly)
                        .font(.caption.weight(.black))
                        .foregroundStyle(NeonTheme.magenta)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .animation(.easeOut(duration: 0.35), value: completedOrderFlash)
            .animation(.easeOut(duration: 0.35), value: rewardFly)
        }
        .frame(height: orders.isEmpty ? 0 : 44)
    }

    private var toastBanner: some View {
        Group {
            if let toastText {
                Text(toastText)
                    .font(.system(.title3, design: .rounded).weight(.black))
                    .foregroundStyle(toastText.contains("CHAIN") ? NeonTheme.magenta : NeonTheme.teal)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(Color.black.opacity(0.72))
                    .overlay(Rectangle().fill(NeonTheme.teal.opacity(0.35)).frame(height: 2), alignment: .bottom)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(height: toastText == nil ? 0 : 44)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: toastText)
    }

    private var previewHoldBar: some View {
        HStack(spacing: 12) {
            VStack(spacing: 4) {
                Text("NEXT").font(.system(size: 9, weight: .black)).foregroundStyle(NeonTheme.muted)
                HStack(spacing: 6) {
                    ForEach(Array(preview.prefix(2).enumerated()), id: \.offset) { _, id in
                        BundleImage(name: JunkCatalog.textureName(for: id))
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                    }
                }
            }
            Spacer()
            Text(playMode == .daily ? "DAILY" : (playMode == .shift ? "SHIFT" : "ENDLESS"))
                .font(.caption2.weight(.black))
                .foregroundStyle(NeonTheme.teal)
            Spacer()
            Button {
                scene.stash()
                AudioService.shared.playSFX("ui")
                syncHUD()
            } label: {
                VStack(spacing: 4) {
                    Text("HOLD").font(.system(size: 9, weight: .black)).foregroundStyle(NeonTheme.muted)
                    if let holdItem {
                        BundleImage(name: JunkCatalog.textureName(for: holdItem))
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(NeonTheme.teal.opacity(0.4), lineWidth: 1)
                            .frame(width: 28, height: 28)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }

    private var raccoonAsset: String {
        switch raccoonMood {
        case .cheer: return "RaccoonCheer"
        case .panic: return "RaccoonPanic"
        case .idle: return "RaccoonIdle"
        }
    }

    private var gestureHint: some View {
        Text("Drag anywhere · Tap rotate · Swipe down to drop")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(NeonTheme.muted.opacity(0.85))
            .padding(.vertical, 6)
            .accessibilityLabel("Drag anywhere to move, tap to rotate, swipe down to drop")
    }

    private var classicPad: some View {
        VStack(spacing: 8) {
            HStack {
                pad("◀") { scene.moveLeft() }
                pad("↻") { scene.rotate(); AudioService.shared.playSFX("ui") }
                pad("▶") { scene.moveRight() }
                pad("Stash") { scene.stash() }
            }
            HStack {
                pad("Soft") { scene.soft() }
                pad("DROP") { scene.hard(); AudioService.shared.playSFX("lock"); HapticsService.shared.lock() }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func pad(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(.white)
                .background(NeonTheme.panel)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(NeonTheme.teal.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func syncHUD() {
        hudScore = scene.engine.state.score
        hudLevel = scene.engine.state.level
        pressMeter = scene.engine.state.pressMeter
        pressMax = scene.engine.state.pressMeterMax
        snatchReady = scene.engine.state.snatchAvailable
        orders = scene.engine.state.orders
        raccoonMood = scene.raccoonMood
        preview = scene.engine.peekNext(2)
        holdItem = scene.engine.state.hold
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
        // One banner at a time — queue extras instead of stacking.
        toastQueue.append(text)
        pumpToast()
    }

    private func pumpToast() {
        guard toastTask == nil, let next = toastQueue.first else { return }
        toastText = next
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            if !Task.isCancelled {
                toastText = nil
                if !toastQueue.isEmpty { toastQueue.removeFirst() }
                toastTask = nil
                pumpToast()
            }
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
        scene.configureForProMotion(false)
        LaunchTiming.markPlayTap()
        AudioService.shared.applyPersistedMute()
        // Demo/shot paths skip the ident — still warm textures before first board paint.
        AssetPreloader.preloadDuringIdent()
        let shot = UserDefaults.standard.string(forKey: "trashStack.shotActive")
            ?? PlayerProfile.shotArgument()
        let auto = shot == "demo" || shot == "autoplay" || ProcessInfo.processInfo.arguments.contains("-autoplay")
        scene.autoplay = auto
        let modeShot: String? = {
            if let shot { return shot }
            if playMode == .daily { return "daily" }
            return nil
        }()
        // Apply board content immediately so the first SpriteKit paint is a filled bin, not gray empty.
        if let modeShot, ["game", "gameplay", "compactor", "press", "recycle", "revive", "demo", "autoplay", "daily"].contains(modeShot) {
            scene.applyShot(modeShot)
            if modeShot == "revive" {
                scene.autoplay = false
                raccoonMood = .panic
                nearMiss = true
                // Smoke-only staged board — lock sheet score to that board, not a stale HUD.
                captureGameOverScore(scene.engine.state.score)
                lastState = scene.engine.state
                syncHUD()
                // Defer past first layout — same-turn sheet flags no-op on soft
                // switches; a short beat keeps magenta/teal markers in the frame.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showContinue = true
                }
            }
        } else if playMode == .daily {
            scene.applyShot("daily")
        }
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
                            // Soft land — lower thud so hard drops still feel bigger.
                            AudioService.shared.playSFX("lock", pitch: 0.85)
                            HapticsService.shared.lock()
                        }
                    case .recycled:
                        let combo = max(1, scene.engine.state.combo)
                        let pitch = 1.0 + Double(combo) * 0.12
                        AudioService.shared.playSFX("recycle", pitch: pitch)
                        if combo >= 2 {
                            AudioService.shared.playSFX("combo", pitch: min(1.9, pitch + 0.08))
                        }
                        if combo >= 4 {
                            AudioService.shared.playSFX("levelup", pitch: 1.15)
                        }
                        HapticsService.shared.recycle()
                        Task { await GameKitService.shared.reportAchievement(AchievementID.firstRecycle) }
                        if scene.engine.state.combo >= 5 {
                            Task { await GameKitService.shared.reportAchievement(AchievementID.chainFive) }
                        }
                    case .pressed:
                        AudioService.shared.playSFX("crush")
                        HapticsService.shared.clear()
                        Task { await GameKitService.shared.reportAchievement(AchievementID.pressSlam) }
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

    @MainActor
    private func captureGameOverScore(_ score: Int) {
        overScore = score
        hudScore = score
        displayScore = score
        overBestBefore = max(profile.highScore, profile.endlessHighScore)
        isNewBest = score > overBestBefore
        sheetScore = 0
        animateSheetScore(to: score)
    }

    @MainActor
    private func animateSheetScore(to target: Int) {
        sheetScoreAnimTask?.cancel()
        guard target > 0 else {
            sheetScore = target
            return
        }
        sheetScoreAnimTask = Task { @MainActor in
            let steps = min(36, max(12, target / 180))
            let start = 0
            for step in 1...steps {
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: 28_000_000)
                if Task.isCancelled { return }
                let t = Double(step) / Double(steps)
                let eased = 1 - pow(1 - t, 3)
                sheetScore = start + Int(Double(target) * eased)
            }
            sheetScore = target
            if isNewBest {
                AudioService.shared.playSFX("levelup", pitch: 1.2)
                HapticsService.shared.clear()
            }
        }
    }

    @MainActor
    private func handleGameOver(_ state: GameState) async {
        lastState = state
        // Prefer the locked top-out score if something mutated state afterward.
        if overScore == 0 { captureGameOverScore(state.score) }
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
                await GameKitService.shared.submitScore(scored, leaderboardID: "trashstack_endless")
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
