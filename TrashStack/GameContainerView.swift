// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import SwiftUI
import SpriteKit
import GameRender
import GameCore
import Services

struct GameContainerView: View {
    @Binding var screen: AppScreen
    @Binding var showNotifPrompt: Bool
    @EnvironmentObject var profile: PlayerProfile
    @State private var scene = CompactorScene(size: CGSize(width: 390, height: 780))
    @State private var showContinue = false
    @State private var lastState: GameState?
    @State private var continued = false
    @State private var hudScore = 0
    @State private var hudLevel = 1

    var body: some View {
        ZStack {
            AlleyBackdrop()
            VStack(spacing: 0) {
                HStack {
                    NeonButton(title: "Lobby", style: .ghost) {
                        AudioService.shared.playMusic("menu_loop")
                        screen = .title
                    }
                    .frame(width: 88)
                    Spacer()
                    VStack(spacing: 2) {
                        Text("SCORE \(hudScore)").font(.caption.monospacedDigit().weight(.bold)).foregroundStyle(.white)
                        Text("LVL \(hudLevel)").font(.caption2.monospacedDigit()).foregroundStyle(NeonTheme.teal)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        CurrencyChip(kind: .scrap, value: profile.scrap)
                        Text("HI \(profile.highScore)").font(.caption2).foregroundStyle(NeonTheme.muted)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 6)

                SpriteView(scene: scene, options: [.allowsTransparency])
                    .ignoresSafeArea(edges: .horizontal)
                    .padding(.horizontal, 4)

                if profile.classicButtons {
                    classicPad
                } else {
                    gestureHint
                }

                Button {
                    scene.magnet()
                    AudioService.shared.playSFX("magnet")
                    HapticsService.shared.tap()
                } label: {
                    HStack(spacing: 8) {
                        Image("MagnetIcon").resizable().frame(width: 28, height: 28)
                        Text("MAGNET \(scene.engine.state.magnetCharge)")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.black)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(colors: [NeonTheme.teal, NeonTheme.magenta], startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.bottom, 10)
            }
        }
        .onAppear(perform: bootstrap)
        .sheet(isPresented: $showContinue) {
            ZStack {
                NeonTheme.bgBottom.ignoresSafeArea()
                NeonPanel {
                    VStack(spacing: 16) {
                        Image("RaccoonPanic").resizable().scaledToFit().frame(height: 96)
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
                        NeonButton(title: "Stack out", style: .ghost) {
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

    private var gestureHint: some View {
        Text("Drag · Tap rotate · Swipe down soft · Flick hard · Swipe up stash")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(NeonTheme.muted)
            .padding(.vertical, 8)
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
                pad("HARD") { scene.hard(); AudioService.shared.playSFX("lock"); HapticsService.shared.lock() }
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

    private func bootstrap() {
        scene.scaleMode = .resizeFill
        scene.configureForProMotion(true)
        let shot = UserDefaults.standard.string(forKey: "trashStack.shotActive")
        let auto = shot == "demo" || shot == "autoplay" || ProcessInfo.processInfo.arguments.contains("-autoplay")
        scene.autoplay = auto
        if let shot, ["game", "gameplay", "compactor", "recycle", "revive", "demo", "autoplay"].contains(shot) {
            scene.applyShot(shot)
            if shot == "recycle" || shot == "compactor" || shot == "demo" {
                scene.autoplay = true
            }
            if shot == "revive" {
                scene.autoplay = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    showContinue = true
                }
            }
        }
        scene.onGameOver = { state in
            Task { @MainActor in
                hudScore = state.score
                await handleGameOver(state)
            }
        }
        scene.onEvents = { events in
            Task { @MainActor in
                hudScore = scene.engine.state.score
                hudLevel = scene.engine.state.level
                for e in events {
                    switch e {
                    case .locked:
                        AudioService.shared.playSFX("lock")
                        HapticsService.shared.lock()
                    case .cleared(let rows, _, _):
                        AudioService.shared.playSFX("crush")
                        HapticsService.shared.clear()
                        if rows.count >= 3 {
                            AudioService.shared.playSFX("levelup", pitch: 1.1)
                        }
                    case .recycled:
                        let pitch = 1.0 + Double(scene.engine.state.combo) * 0.08
                        AudioService.shared.playSFX("recycle", pitch: pitch)
                        AudioService.shared.playSFX("combo", pitch: pitch)
                        HapticsService.shared.recycle()
                    case .leveledUp:
                        AudioService.shared.playSFX("levelup")
                    case .magnetUsed:
                        AudioService.shared.playSFX("magnet")
                    default: break
                    }
                }
                UserDefaults.standard.set(scene.measuredFPS, forKey: "trashStack.measuredFPS")
            }
        }
        AudioService.shared.playMusic("game_loop")
        hudScore = scene.engine.state.score
        hudLevel = scene.engine.state.level
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
        if state.score > profile.highScore {
            profile.highScore = state.score
        }
        if state.score > 0 && !profile.firstWin {
            profile.firstWin = true
            profile.persist()
            if !profile.notifAsked {
                showNotifPrompt = true
            }
        }
        profile.persist()
        await AdsService.shared.maybeShowInterstitial()
        continued = false
        AudioService.shared.playMusic("menu_loop")
        screen = .title
    }
}
