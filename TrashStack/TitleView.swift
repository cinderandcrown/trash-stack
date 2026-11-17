// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import SwiftUI
import Services

struct TitleView: View {
    @Binding var screen: AppScreen
    @Binding var showNotifPrompt: Bool
    @EnvironmentObject var profile: PlayerProfile
    @State private var bob = false
    @State private var heavyReady = false

    var body: some View {
        ZStack {
            // First paint: gradient only (AlleyBackground decode is the main-thread stall).
            NeonTheme.alleyGradient.ignoresSafeArea()
            if heavyReady {
                AlleyBackdrop(includeGradient: false)
            }
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
                Text("Recycling Night Shift")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
                Text("Match materials · slam the press · fill orders")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.72))
                HStack(spacing: 10) {
                    CurrencyChip(kind: .scrap, value: profile.scrap)
                    CurrencyChip(kind: .gems, value: profile.gems)
                }
                NeonButton(title: "PLAY") {
                    AdsService.shared.noteRunStarted()
                    AudioService.shared.playMusic("game_loop")
                    LaunchTiming.markPlayTap()
                    screen = .modes
                }
                .padding(.horizontal, 36)

                HStack(spacing: 10) {
                    if profile.dailyStreak > 0 {
                        Text("Streak \(profile.dailyStreak)d")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(NeonTheme.magenta)
                    }
                    if profile.cratesReady > 0 {
                        Text("Crate ×\(profile.cratesReady)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(NeonTheme.teal)
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    NeonButton(title: "Junkyard", style: .ghost) { screen = .base }
                    NeonButton(title: "Season Pass", style: .ghost) { screen = .pass }
                    NeonButton(title: "Shop", style: .ghost) { screen = .shop }
                    NeonButton(title: "Settings", style: .ghost) { screen = .settings }
                    NeonButton(title: profile.cratesReady > 0 ? "Open Crate" : "Crate…", style: .secondary) {
                        screen = .quests // crate ceremony lives here for v1
                    }
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
            // Idempotent: publisher ident stamps first frame on cold launch; this covers skip/shot paths.
            LaunchTiming.markFirstTitleFrame()
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                bob = true
            }
            Task { @MainActor in
                await Task.yield()
                heavyReady = true
                HapticsService.shared.prepare()
                AudioService.shared.prepare()
                AudioService.shared.playMusic("menu_loop")
            }
        }
    }
}
