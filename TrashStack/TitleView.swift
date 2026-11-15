// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import SwiftUI
import Services

struct TitleView: View {
    @Binding var screen: AppScreen
    @Binding var showNotifPrompt: Bool
    @EnvironmentObject var profile: PlayerProfile
    @State private var bob = false

    var body: some View {
        ZStack {
            AlleyBackdrop()
            VStack(spacing: 14) {
                Spacer(minLength: 24)
                BundleImage(name: "RaccoonIdle")
                    .scaledToFit()
                    .frame(width: 140, height: 140)
                    .offset(y: bob ? -6 : 6)
                    .shadow(color: NeonTheme.teal.opacity(0.45), radius: 18)
                    .accessibilityLabel("Trash Panda")
                Text("TRASH STACK")
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: [NeonTheme.teal, NeonTheme.magenta], startPoint: .leading, endPoint: .trailing)
                    )
                Text("Neon junk. Night shift.")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
                HStack(spacing: 10) {
                    CurrencyChip(kind: .scrap, value: profile.scrap)
                    CurrencyChip(kind: .gems, value: profile.gems)
                }
                NeonButton(title: "PLAY") {
                    AdsService.shared.noteRunStarted()
                    AudioService.shared.playMusic("game_loop")
                    if !profile.tutorialDone {
                        screen = .tutorial
                    } else {
                        screen = .game
                    }
                }
                .padding(.horizontal, 36)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    NeonButton(title: "Junkyard", style: .ghost) { screen = .base }
                    NeonButton(title: "Season Pass", style: .ghost) { screen = .pass }
                    NeonButton(title: "Shop", style: .ghost) { screen = .shop }
                    NeonButton(title: "Quests", style: .ghost) { screen = .quests }
                    NeonButton(title: "Settings", style: .ghost) { screen = .settings }
                    NeonButton(title: "Spin", style: .secondary) { AudioService.shared.playSFX("combo", pitch: 1.2) }
                }
                .padding(.horizontal, 22)

                Text("Free to play · odds shown · no real-money gambling")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.7))
                Spacer(minLength: 12)
            }
            .padding(.horizontal, 8)
        }
        .onAppear {
            AudioService.shared.playMusic("menu_loop")
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                bob = true
            }
        }
    }
}
