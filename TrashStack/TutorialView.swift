// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import SwiftUI
import SpriteKit
import GameRender
import GameCore
import Services

/// Interactive first shift (~30–45s): guaranteed almost-cluster → first chain → press.
/// Text cards are a tiny bark overlay, not the lesson.
struct TutorialView: View {
    @Binding var screen: AppScreen
    @EnvironmentObject var profile: PlayerProfile
    @State private var scene = CompactorScene(size: CGSize(width: 390, height: 620))
    @State private var bark = "Drag the can onto the metal pile"
    @State private var step = 0
    @State private var recycled = false
    @State private var pressed = false

    var body: some View {
        ZStack {
            NeonTheme.playChrome.ignoresSafeArea()
            VStack(spacing: 8) {
                Text("FIRST SHIFT")
                    .font(.system(.title3, design: .rounded).weight(.black))
                    .foregroundStyle(NeonTheme.teal)
                    .padding(.top, 4)
                Text(bark)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .animation(.easeOut(duration: 0.2), value: bark)

                SpriteView(scene: scene)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 10)
                    .layoutPriority(1)

                HStack(spacing: 12) {
                    Button {
                        scene.slamPress()
                        AudioService.shared.playSFX("crush")
                    } label: {
                        Text(scene.engine.state.pressMeter >= scene.engine.state.pressMeterMax ? "SLAM PRESS" : "PRESS…")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(scene.engine.state.pressMeter >= scene.engine.state.pressMeterMax ? NeonTheme.magenta : NeonTheme.panel)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(scene.engine.state.pressMeter < scene.engine.state.pressMeterMax)

                    if pressed || (recycled && step >= 2) {
                        NeonButton(title: "Onto the yard") {
                            finish(toGame: true)
                        }
                    }
                }
                .padding(.horizontal, 16)

                Button("Skip") { finish(toGame: false) }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NeonTheme.muted)
                    .padding(.bottom, 8)
            }
            .safeAreaPadding(.top, 8)
            .safeAreaPadding(.bottom, 8)
        }
        .onAppear(perform: bootstrap)
    }

    private func bootstrap() {
        scene.feel = ConfigLoader.feelOrFallback()
        scene.onEvents = { events in
            for e in events {
                switch e {
                case .recycled:
                    if !recycled {
                        recycled = true
                        step = 2
                        bark = "Nice! Sucked into the chute — now slam PRESS"
                        AudioService.shared.playSFX("recycle", pitch: 1.15)
                        scene.engine.fillPressMeter()
                    }
                case .pressed:
                    pressed = true
                    bark = "That's the night shift. You're ready."
                    AudioService.shared.playSFX("crush")
                default: break
                }
            }
        }
        scene.onToast = { text in
            if text.contains("CHAIN") || text.contains("RECYCLE") {
                bark = text
            }
        }
        // applyShot rebuilds + presents juice; leave press nearly ready.
        scene.applyShot("ftue")
        scene.engine.state.pressMeter = max(0, scene.engine.state.pressMeterMax - 2)
        scene.render(immediate: true)
        bark = "Drag the falling can into the metal — make 4+ to recycle"
        AudioService.shared.playSFX("ui")
    }

    private func finish(toGame: Bool) {
        profile.tutorialDone = true
        profile.persist()
        AudioService.shared.playSFX("levelup")
        screen = toGame ? .game : .title
    }
}
