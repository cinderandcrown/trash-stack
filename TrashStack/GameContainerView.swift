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
    @State private var pressMeter = 0
    @State private var pressMax = 8
    @State private var snatchReady = true
    @State private var orders: [OrderTicket] = []
    @State private var preview: [JunkID] = []
    @State private var holdItem: JunkID? = nil
    @State private var nearMiss = false

    var body: some View {
        VStack(spacing: 0) {
            hudBar
            orderStrip
            previewHoldBar

            SpriteView(scene: scene)
                .ignoresSafeArea(edges: .horizontal)
                .layoutPriority(1)
                .overlay(alignment: .top) {
                    if nearMiss {
                        Text("BIN ALMOST FULL")
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
                Button {
                    scene.slamPress()
                    AudioService.shared.playSFX("crush")
                    HapticsService.shared.clear()
                    syncHUD()
                } label: {
                    VStack(spacing: 4) {
                        Text("PRESS")
                            .font(.caption.weight(.black))
                        ProgressView(value: Double(pressMeter), total: Double(max(1, pressMax)))
                            .tint(pressMeter >= pressMax ? NeonTheme.magenta : NeonTheme.teal)
                        Text(pressMeter >= pressMax ? "READY" : "\(pressMeter)/\(pressMax)")
                            .font(.caption2.monospacedDigit().weight(.bold))
                    }
                    .foregroundStyle(pressMeter >= pressMax ? .black : .white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(
                        LinearGradient(
                            colors: pressMeter >= pressMax
                                ? [NeonTheme.magenta, NeonTheme.teal]
                                : [NeonTheme.panel, NeonTheme.panel],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(pressMeter < pressMax)

                Button {
                    scene.magnet()
                    AudioService.shared.playSFX("magnet")
                    HapticsService.shared.tap()
                    syncHUD()
                } label: {
                    HStack(spacing: 8) {
                        BundleImage(name: raccoonAsset).frame(width: 28, height: 28)
                        Text(snatchReady ? "SNATCH" : "USED")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.black)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: snatchReady
                                ? [NeonTheme.teal, NeonTheme.magenta]
                                : [NeonTheme.panel, NeonTheme.panel],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                    .opacity(snatchReady ? 1 : 0.55)
                }
                .buttonStyle(.plain)
                .disabled(!snatchReady)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(Color(red: 0.02, green: 0.02, blue: 0.06).ignoresSafeArea())
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
                    VStack(spacing: 16) {
                        BundleImage(name: "RaccoonPanic")
                            .scaledToFit()
                            .frame(width: 110, height: 110)
                        Text("ONE MORE?").font(.title2.bold()).foregroundStyle(NeonTheme.magenta)
                        Text("Watch a rewarded ad to revive once this run.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(NeonTheme.muted)
                        NeonButton(title: "Revive (ad)") {
                            Task {
                                let ok = await AdsService.shared.showRewarded(placement: "revive")
                                showContinue = false
                                if ok {
                                    continued = true
                                    scene.revive()
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
            .presentationDetents([.medium])
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
                    VStack(alignment: .leading, spacing: 2) {
                        Text(order.label)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(order.done ? NeonTheme.teal : .white)
                            .lineLimit(1)
                        ProgressView(value: Double(min(order.progress, order.target)), total: Double(max(1, order.target)))
                            .tint(order.done ? NeonTheme.teal : NeonTheme.magenta)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: orders.isEmpty ? 0 : 44)
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
        Text("Drag · Tap rotate · Flick drop · PRESS when ready · SNATCH once")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(NeonTheme.muted)
            .padding(.vertical, 6)
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
        preview = Array(scene.engine.state.queue.prefix(2))
        holdItem = scene.engine.state.hold
        let wasNear = nearMiss
        nearMiss = scene.engine.isNearOverflow()
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
        let shot = UserDefaults.standard.string(forKey: "trashStack.shotActive")
            ?? PlayerProfile.shotArgument()
        let auto = shot == "demo" || shot == "autoplay" || ProcessInfo.processInfo.arguments.contains("-autoplay")
        scene.autoplay = auto
        scene.onGameOver = { state in
            Task { @MainActor in
                hudScore = state.score
                raccoonMood = .panic
                await handleGameOver(state)
            }
        }
        scene.onEvents = { [weak scene] events in
            Task { @MainActor in
                guard let scene else { return }
                syncHUD()
                for e in events {
                    switch e {
                    case .locked:
                        AudioService.shared.playSFX("lock")
                        HapticsService.shared.lock()
                    case .recycled:
                        let pitch = 1.0 + Double(scene.engine.state.combo) * 0.1
                        AudioService.shared.playSFX("recycle", pitch: pitch)
                        AudioService.shared.playSFX("combo", pitch: min(1.8, pitch + 0.05))
                        HapticsService.shared.recycle()
                        Task { await GameKitService.shared.reportAchievement(AchievementID.firstRecycle) }
                        if scene.engine.state.combo >= 5 {
                            Task { await GameKitService.shared.reportAchievement(AchievementID.chainFive) }
                        }
                    case .pressed:
                        AudioService.shared.playSFX("crush")
                        HapticsService.shared.clear()
                        Task { await GameKitService.shared.reportAchievement(AchievementID.pressSlam) }
                    case .orderCompleted:
                        AudioService.shared.playSFX("levelup")
                    case .snatchUsed:
                        AudioService.shared.playSFX("magnet")
                        Task { await GameKitService.shared.reportAchievement(AchievementID.snatchUsed) }
                    case .leveledUp:
                        AudioService.shared.playSFX("levelup")
                    default: break
                    }
                }
                UserDefaults.standard.set(scene.measuredFPS, forKey: "trashStack.measuredFPS")
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            let modeShot: String? = {
                if let shot { return shot }
                if playMode == .daily { return "daily" }
                return nil
            }()
            if let modeShot, ["game", "gameplay", "compactor", "press", "recycle", "revive", "demo", "autoplay", "daily"].contains(modeShot) {
                scene.applyShot(modeShot)
                if modeShot == "demo" || modeShot == "autoplay" {
                    scene.autoplay = true
                    let playScene = scene
                    playScene.startDemoChoreography {
                        Task { @MainActor in
                            raccoonMood = .panic
                            showContinue = true
                            try? await Task.sleep(nanoseconds: 2_200_000_000)
                            showContinue = false
                            continued = true
                            playScene.revive()
                            AudioService.shared.playSFX("levelup")
                        }
                    }
                }
                if modeShot == "revive" {
                    scene.autoplay = false
                    showContinue = true
                    raccoonMood = .panic
                }
            } else if playMode == .daily {
                scene.applyShot("daily")
            }
            syncHUD()
            displayScore = scene.engine.state.score
            AudioService.shared.playMusic("game_loop")
        }
        syncHUD()
        displayScore = scene.engine.state.score
    }

    @MainActor
    private func handleGameOver(_ state: GameState) async {
        lastState = state
        if !continued {
            showContinue = true
            return
        }
        await finalizeOver()
    }

    @MainActor
    private func finalizeOver() async {
        guard let state = lastState ?? Optional(scene.engine.state) else { return }
        profile.addScrap(state.runScrap)
        profile.battlePassXP += state.lines * 2 + 5
        for order in state.orders where order.done {
            profile.addGems(2)
            profile.battlePassXP += 15
        }
        if state.score > profile.highScore {
            profile.highScore = state.score
        }
        if playMode == .endless {
            if state.score > profile.endlessHighScore {
                profile.endlessHighScore = state.score
            }
            await GameKitService.shared.submitScore(state.score, leaderboardID: "trashstack_endless")
        }
        if playMode == .daily {
            let stars = state.orders.filter(\.done).count
            let card = DailyDumpster.shareCard(
                dayKey: DailyDumpster.dayKey(),
                score: state.score,
                stars: min(3, max(1, stars)),
                materialGrid: scene.engine.materialShareGrid()
            )
            profile.markDailyComplete(score: state.score)
            await GameKitService.shared.submitScore(state.score, leaderboardID: "trashstack_daily")
            await GameKitService.shared.reportAchievement(AchievementID.dailyClear)
            if profile.dailyStreak >= 7 {
                await GameKitService.shared.reportAchievement(AchievementID.streakSeven)
            }
            profile.persist()
            continued = false
            AudioService.shared.playMusic("menu_loop")
            onDailyFinished?(state.score, card)
            return
        }
        if playMode == .shift, state.orders.allSatisfy(\.done) {
            profile.shiftProgress = max(profile.shiftProgress, profile.shiftProgress + 1)
        }
        if state.score > 0 && !profile.firstWin {
            profile.firstWin = true
            profile.persist()
            if !profile.notifAsked {
                showNotifPrompt = true
            }
        }
        // Streak check-in once per day from any completed shift.
        let streak = profile.registerDailyActivity()
        profile.persist()
        await AdsService.shared.maybeShowInterstitial()
        continued = false
        AudioService.shared.playMusic("menu_loop")
        if streak.isNew, streak.scrap > 0 {
            onStreakReward?(streak.streak, streak.scrap, streak.gems)
        } else {
            screen = .title
        }
    }
}
