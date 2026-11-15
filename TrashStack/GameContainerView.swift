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
    @State private var scene = CompactorScene(size: CGSize(width: 390, height: 720))
    @State private var showContinue = false
    @State private var lastState: GameState?
    @State private var continued = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Lobby") { screen = .title }
                Spacer()
                Text("⚙ \(profile.scrap)  ◆ \(profile.gems)")
                    .font(.caption.monospacedDigit())
                Spacer()
                Text("HI \(profile.highScore)")
                    .font(.caption)
            }
            .padding()

            SpriteView(scene: scene)
                .ignoresSafeArea(edges: .horizontal)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 8)

            controls
        }
        .onAppear {
            scene.scaleMode = .resizeFill
            let shot = UserDefaults.standard.string(forKey: "trashStack.shotActive")
            let auto = shot == "demo" || shot == "autoplay" || ProcessInfo.processInfo.arguments.contains("-autoplay")
            scene.autoplay = auto
            scene.onGameOver = { state in
                Task { @MainActor in
                    await handleGameOver(state)
                }
            }
            if shot == "recycle" || shot == "compactor" || shot == "revive" {
                scene.autoplay = true
            }
            if shot == "revive" {
                // Force the continue sheet for App Store evidence.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    showContinue = true
                }
            }
            scene.configureForProMotion(true)
        }
        .sheet(isPresented: $showContinue) {
            VStack(spacing: 16) {
                Text("ONE MORE?").font(.title2.bold())
                Text("Watch a rewarded ad to revive once this run.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Revive (ad)") {
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
                .buttonStyle(.borderedProminent)
                Button("Stack out") {
                    showContinue = false
                    Task { await finalizeOver() }
                }
            }
            .padding()
            .presentationDetents([.medium])
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack {
                pad("◀") { scene.moveLeft() }
                pad("↻") { scene.rotate() }
                pad("▶") { scene.moveRight() }
                pad("Stash") { scene.stash() }
                pad("Magnet") { scene.magnet(); HapticsService.shared.tap() }
            }
            HStack {
                pad("Soft") { scene.soft() }
                pad("HARD") { scene.hard(); AudioService.shared.blip(frequency: 220) }
            }
        }
        .padding()
    }

    private func pad(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .foregroundStyle(.white)
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
        screen = .title
    }
}
