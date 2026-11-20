// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import SwiftUI
import SpriteKit
import GameCore
import GameRender
import Services

/// TRASH TALK 1v1 — last bin standing. No paid entry, no wagers, no real-value prizes.
struct TrashTalkView: View {
    @Binding var screen: AppScreen
    @EnvironmentObject var profile: PlayerProfile

    @State private var scene = CompactorScene(size: CGSize(width: 320, height: 560))
    @State private var phase: TrashTalkMatchPhase = .idle
    @State private var countdown = 3
    @State private var vsBot = false
    @State private var rivalName = "Rival"
    @State private var seed: UInt64 = 1
    @State private var bot = TrashTalkBot(seed: 1)
    @State private var junkSent = 0
    @State private var junkReceived = 0
    @State private var warnProgress: Double = 0
    @State private var pendingWarnRows = 0
    @State private var rivalFill: Double = 0.2
    @State private var result: TrashTalkResult?
    @State private var raccoonMood: CompactorScene.RaccoonMood = .idle
    @State private var raccoonBounce: CGFloat = 1
    @State private var inviteFriend = false
    @State private var winStreak = UserDefaults.standard.integer(forKey: "tt.winStreak")
    @State private var tickTask: Task<Void, Never>?
    @State private var digestAcc: Double = 0

    var body: some View {
        ZStack {
            NeonTheme.alleyGradient.ignoresSafeArea()
            switch phase {
            case .idle:
                lobby
            case .matchmaking:
                matchmakingPane
            case .countdown:
                countdownPane
            case .playing:
                playPane
            case .finished:
                resultsPane
            }
        }
        .onAppear {
            GameKitService.shared.configureAccessPoint(show: true)
            wireMatchCallbacks()
        }
        .onDisappear {
            tickTask?.cancel()
            GameKitService.shared.cancelMatchmaking()
            GameKitService.shared.disconnectMatch()
            GameKitService.shared.configureAccessPoint(show: false)
        }
#if canImport(UIKit)
        .sheet(item: Binding(
            get: { GameKitService.shared.authViewController.map(AuthVCBox.init) },
            set: { if $0 == nil { GameKitService.shared.authViewController = nil } }
        )) { box in
            AuthVCRepresentable(controller: box.vc)
        }
#endif
    }

    private var lobby: some View {
        VStack(spacing: 16) {
            MetaChromeHeader(title: "TRASH TALK") { screen = .modes }
            BundleImage(name: "BanditHero")
                .scaledToFit()
                .frame(width: 120, height: 120)
            Text("1v1 · last bin standing")
                .font(.title3.weight(.black))
                .foregroundStyle(.white)
            Text("Same piece seed. Clear clusters to send junk. No entry fees, no prizes.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(NeonTheme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            NeonButton(title: "Quick Match") {
                inviteFriend = false
                beginMatchmaking()
            }
            .padding(.horizontal, 36)
            NeonButton(title: "Invite a Friend", style: .secondary) {
                inviteFriend = true
                beginMatchmaking()
            }
            .padding(.horizontal, 36)
            NeonButton(title: "Practice vs Bot", style: .ghost) {
                GameKitService.shared.startBotMatch(reason: "practice")
            }
            .padding(.horizontal, 36)
            if winStreak > 0 {
                Text("Win streak \(winStreak)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(NeonTheme.magenta)
            }
            Spacer(minLength: 0)
        }
    }

    private var matchmakingPane: some View {
        VStack(spacing: 18) {
            ProgressView()
                .tint(NeonTheme.teal)
            Text(inviteFriend ? "Waiting on your friend…" : "Finding a rival…")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
            Text("If nobody shows in \(Int(TrashTalkRules.matchmakingBotFallbackSec))s, you get a labeled bot.")
                .font(.caption)
                .foregroundStyle(NeonTheme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            NeonButton(title: "Cancel", style: .ghost) {
                GameKitService.shared.cancelMatchmaking()
                phase = .idle
            }
        }
    }

    private var countdownPane: some View {
        VStack(spacing: 12) {
            Text(vsBot ? "vs Dumpster Bot" : "vs \(rivalName)")
                .font(.caption.weight(.bold))
                .foregroundStyle(NeonTheme.teal)
            Text("\(countdown)")
                .font(.system(size: 96, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Text("Get ready")
                .foregroundStyle(NeonTheme.muted)
        }
    }

    private var playPane: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    forfeit()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(NeonTheme.teal)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                BundleImage(name: raccoonAsset)
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                    .scaleEffect(raccoonBounce)

                VStack(alignment: .leading, spacing: 2) {
                    Text(vsBot ? "Dumpster Bot" : rivalName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                    Text("Junk sent \(junkSent) · got \(junkReceived)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(NeonTheme.muted)
                }
                Spacer()
                rivalMiniBoard
            }
            .padding(.horizontal, 12)

            if pendingWarnRows > 0 {
                VStack(spacing: 4) {
                    Text("JUNK INCOMING ×\(pendingWarnRows)")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(NeonTheme.magenta)
                    ProgressView(value: warnProgress)
                        .tint(NeonTheme.magenta)
                }
                .padding(.horizontal, 16)
            }

            SpriteView(scene: scene)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 10)
                .layoutPriority(1)

            classicPad
        }
    }

    private var rivalMiniBoard: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.45))
            RoundedRectangle(cornerRadius: 6)
                .fill(NeonTheme.magenta.opacity(0.55))
                .frame(height: 56 * rivalFill)
        }
        .frame(width: 36, height: 56)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(NeonTheme.teal.opacity(0.6), lineWidth: 1)
        )
        .accessibilityLabel("Rival bin fill")
    }

    private var classicPad: some View {
        let das = scene.feel.dasDelaySec
        let arr = scene.feel.arrIntervalSec
        return HStack(spacing: 10) {
            RepeatPadButton(title: "◀", accessibility: "Left", dasDelay: das, repeatInterval: arr) {
                scene.moveLeft()
            }
            RepeatPadButton(title: "↻", accessibility: "Rotate", dasDelay: 99, repeatInterval: 99, fireOnce: true) {
                scene.rotate()
            }
            RepeatPadButton(title: "▶", accessibility: "Right", dasDelay: das, repeatInterval: arr) {
                scene.moveRight()
            }
            RepeatPadButton(title: "SOFT", accessibility: "Soft", dasDelay: 0.12, repeatInterval: scene.feel.softRepeatSec) {
                scene.soft()
            }
            RepeatPadButton(title: "DROP", accessibility: "Drop", emphasis: true, dasDelay: 99, repeatInterval: 99, fireOnce: true) {
                scene.hard()
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    private var resultsPane: some View {
        VStack(spacing: 14) {
            BundleImage(name: result?.won == true ? "RaccoonCheer" : "RaccoonGameOver")
                .frame(width: 100, height: 100)
            Text(result?.won == true ? "YOU WIN" : "BIN TOPPED OUT")
                .font(.largeTitle.weight(.black))
                .foregroundStyle(result?.won == true ? NeonTheme.teal : NeonTheme.magenta)
            if result?.vsBot == true {
                Text("Opponent: Dumpster Bot")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(NeonTheme.muted)
            }
            if let result {
                Text("Junk sent \(result.junkSent) · received \(result.junkReceived) · score \(result.score)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
            }
            NeonButton(title: "Rematch") { rematch() }
                .padding(.horizontal, 40)
            NeonButton(title: "Beat my score (friends)", style: .secondary) {
                let sc = result?.score ?? scene.engine.state.score
                GameKitService.shared.challengeBeatMyScore(sc)
            }
            .padding(.horizontal, 40)
            NeonButton(title: "Back", style: .ghost) { screen = .modes }
                .padding(.horizontal, 40)
            Spacer(minLength: 0)
        }
        .onAppear {
            GameKitService.shared.configureAccessPoint(show: true, onResults: true)
        }
    }

    private var raccoonAsset: String {
        switch raccoonMood {
        case .cheer: return "RaccoonCheer"
        case .panic: return "RaccoonPanic"
        case .disco: return BundleArt.uiImage("RaccoonDisco") != nil ? "RaccoonDisco" : "RaccoonCheer"
        case .gameOver: return "RaccoonGameOver"
        case .idle: return "RaccoonIdle"
        }
    }

    private func beginMatchmaking() {
        phase = .matchmaking
        GameKitService.shared.startTrashTalkMatchmaking(inviteFriend: inviteFriend)
    }

    private func wireMatchCallbacks() {
        let gk = GameKitService.shared
        gk.onMatchStarted = { seed, bot, name in
            self.seed = seed
            self.vsBot = bot
            self.rivalName = bot ? "Dumpster Bot" : name
            self.junkSent = 0
            self.junkReceived = 0
            self.result = nil
            self.bot = TrashTalkBot(seed: seed)
            self.scene.reset(seed: seed)
            self.scene.autoplay = false
            startCountdown()
        }
        gk.onMatchData = { data, _ in
            guard let msg = TrashTalkWire.decode(data) else { return }
            handleWire(msg)
        }
        gk.onRivalDisconnected = {
            finish(won: true, disconnected: true)
        }
        scene.onEvents = { events in
            handleLocalEvents(events)
        }
    }

    private func startCountdown() {
        phase = .countdown
        countdown = Int(TrashTalkRules.countdownSec)
        tickTask?.cancel()
        tickTask = Task { @MainActor in
            while countdown > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                countdown -= 1
            }
            phase = .playing
            setMood(.idle)
            startPlayLoop()
        }
    }

    private func startPlayLoop() {
        tickTask?.cancel()
        tickTask = Task { @MainActor in
            var last = Date()
            while phase == .playing, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 32_000_000)
                let now = Date()
                let dt = now.timeIntervalSince(last)
                last = now
                _ = scene.tickJunkWarning(dt: dt)
                // Re-publish warn meter from engine state
                pendingWarnRows = scene.engine.state.pendingJunkRows
                if pendingWarnRows > 0 {
                    warnProgress = min(1, scene.engine.state.junkWarnElapsed / max(0.01, scene.engine.state.junkWarnDuration))
                    setMood(.panic)
                }
                if vsBot {
                    let outbound = bot.tick(dt: dt)
                    if outbound > 0 {
                        scene.queueJunk(rows: outbound)
                        junkReceived += outbound
                    }
                    let dig = bot.engine.boardDigest()
                    rivalFill = Double(dig.filled) / 255.0
                    if bot.engine.state.over {
                        finish(won: true, disconnected: false)
                    }
                } else {
                    digestAcc += dt
                    if digestAcc > 0.4 {
                        digestAcc = 0
                        let dig = scene.engine.boardDigest()
                        GameKitService.shared.send(.boardDigest(filled: dig.filled, topY: dig.topY))
                    }
                }
                if scene.engine.state.over {
                    if !vsBot {
                        GameKitService.shared.send(.topOut)
                    }
                    finish(won: false, disconnected: false)
                }
                scene.render(immediate: false)
            }
        }
    }

    private func handleLocalEvents(_ events: [GameEvent]) {
        for e in events {
            switch e {
            case .recycled(let groups, _, _, _, _, _):
                setMood(.cheer)
                let rows = TrashTalkRules.junkRows(clears: groups, combo: max(1, scene.engine.state.combo))
                if rows > 0 {
                    junkSent += rows
                    if vsBot {
                        bot.receiveJunk(rows: rows)
                    } else {
                        GameKitService.shared.send(.junk(rows: UInt8(min(255, rows))))
                    }
                    if junkSent >= 10 {
                        Task { await GameKitService.shared.reportAchievement(AchievementID.sendTenJunk) }
                    }
                    if junkSent >= 50 {
                        Task { await GameKitService.shared.reportAchievement(AchievementID.sendFiftyJunk) }
                    }
                }
                if groups >= 4 {
                    Task { await GameKitService.shared.reportAchievement(AchievementID.fourRowClear) }
                }
            case .locked(let hard):
                if !vsBot {
                    let p = scene.engine.state.active
                    GameKitService.shared.send(.lock(
                        pieceIndex: UInt16(truncatingIfNeeded: scene.engine.lockCount),
                        x: Int8(p?.x ?? 0),
                        y: Int8(p?.y ?? 0),
                        rot: UInt8(p?.rot ?? 0),
                        hard: hard
                    ))
                }
            case .junkIncoming(_, let progress):
                warnProgress = progress
            default: break
            }
        }
    }

    private func handleWire(_ msg: TrashTalkWire) {
        switch msg {
        case .junk(let rows):
            junkReceived += Int(rows)
            scene.queueJunk(rows: Int(rows))
            setMood(.panic)
        case .boardDigest(let filled, _):
            rivalFill = Double(filled) / 255.0
            if rivalFill > 0.7 { setMood(.cheer) }
        case .topOut:
            finish(won: true, disconnected: false)
        case .rematch:
            rematch()
        case .hello(let remoteSeed):
            // Prefer the agreed seed from match attach; accept peer hello if we somehow raced.
            if phase == .matchmaking || phase == .idle {
                seed = remoteSeed
            }
        default: break
        }
    }

    private func finish(won: Bool, disconnected: Bool) {
        guard phase == .playing || phase == .countdown else { return }
        tickTask?.cancel()
        phase = .finished
        setMood(won ? .cheer : .gameOver)
        let scored = scene.engine.state.score
        result = TrashTalkResult(
            won: won,
            vsBot: vsBot,
            junkSent: junkSent,
            junkReceived: junkReceived,
            score: scored
        )
        if !vsBot {
            GameKitService.shared.disconnectMatch()
        }
        Task {
            await GameKitService.shared.submitScore(scored)
            await GameKitService.shared.submitWeeklyScore(scored)
            if won {
                await GameKitService.shared.reportAchievement(AchievementID.firstTrashTalkWin)
                winStreak += 1
                UserDefaults.standard.set(winStreak, forKey: "tt.winStreak")
                if winStreak >= 3 {
                    await GameKitService.shared.reportAchievement(AchievementID.trashTalkWinStreak3)
                }
                if winStreak >= 5 {
                    await GameKitService.shared.reportAchievement(AchievementID.trashTalkWinStreak5)
                }
                // Cross-game: first online (non-bot) win also nudges Bandit of Both Worlds progress.
                if !vsBot {
                    await GameKitService.shared.reportAchievement(AchievementID.banditOfBothWorlds, percent: 50)
                }
            } else if !disconnected {
                winStreak = 0
                UserDefaults.standard.set(0, forKey: "tt.winStreak")
            }
            if scored >= 10_000 {
                await GameKitService.shared.reportAchievement(AchievementID.allTime10k)
            }
            if scored >= 50_000 {
                await GameKitService.shared.reportAchievement(AchievementID.allTime50k)
            }
        }
        _ = disconnected
    }

    private func rematch() {
        if !vsBot {
            GameKitService.shared.send(.rematch)
        }
        junkSent = 0
        junkReceived = 0
        result = nil
        bot = TrashTalkBot(seed: seed &+ 1)
        seed = seed &+ 1
        scene.reset(seed: seed)
        if vsBot {
            startCountdown()
        } else {
            beginMatchmaking()
        }
        Task { await GameKitService.shared.reportAchievement(AchievementID.rematchWin, percent: 0) }
    }

    private func forfeit() {
        if !vsBot { GameKitService.shared.send(.topOut) }
        finish(won: false, disconnected: false)
    }

    private func setMood(_ mood: CompactorScene.RaccoonMood) {
        guard mood != raccoonMood else { return }
        raccoonMood = mood
        raccoonBounce = 0.82
        withAnimation(.spring(response: 0.28, dampingFraction: 0.45)) {
            raccoonBounce = 1
        }
    }
}

#if canImport(UIKit)
import UIKit

private struct AuthVCBox: Identifiable {
    let id = UUID()
    let vc: UIViewController
    init(vc: UIViewController) { self.vc = vc }
}

private struct AuthVCRepresentable: UIViewControllerRepresentable {
    let controller: UIViewController
    func makeUIViewController(context: Context) -> UIViewController { controller }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
#endif
