// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import SwiftUI
import Services
import GameCore

struct ModeSelectView: View {
    @Binding var screen: AppScreen
    @Binding var playMode: PlayMode
    @EnvironmentObject var profile: PlayerProfile

    var body: some View {
        ZStack {
            AlleyBackdrop()
            VStack(spacing: 14) {
                MetaChromeHeader(title: "CHOOSE SHIFT") { screen = .title }
                modeCard(
                    title: "Shift Mode",
                    blurb: "Handcrafted districts · order tickets · 3-star goals",
                    mode: .shift
                )
                modeCard(
                    title: "Endless Night Shift",
                    blurb: "High score · Game Center leaderboard",
                    mode: .endless
                )
                modeCard(
                    title: "Daily Dumpster",
                    blurb: profile.didDailyToday
                        ? "Today’s dump cleared · share your card"
                        : "One seeded puzzle for everyone today",
                    mode: .daily
                )
                Spacer(minLength: 0)
            }
            .padding(.bottom, 12)
        }
    }

    private func modeCard(title: String, blurb: String, mode: PlayMode) -> some View {
        Button {
            playMode = mode
            profile.preferredMode = PlayModePreference(rawValue: mode.rawValue) ?? .endless
            profile.persist()
            AudioService.shared.playSFX("ui")
            if mode == .shift {
                screen = .shiftMap
                return
            }
            if !profile.tutorialDone {
                screen = .tutorial
            } else {
                screen = .game
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                Text(blurb)
                    .font(.caption)
                    .foregroundStyle(NeonTheme.muted)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(NeonTheme.panel.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(NeonTheme.teal.opacity(0.55), lineWidth: 1.2)
            )
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
    }
}

struct StreakRewardView: View {
    @Binding var screen: AppScreen
    @EnvironmentObject var profile: PlayerProfile
    let streak: Int
    let scrap: Int
    let gems: Int

    var body: some View {
        ZStack {
            AlleyBackdrop()
            VStack(spacing: 16) {
                MetaChromeHeader(title: "STREAK") { screen = .title }
                BundleImage(name: "RaccoonCheer")
                    .scaledToFit()
                    .frame(height: 120)
                Text("Day \(streak) Night Shift")
                    .font(.title.weight(.black))
                    .foregroundStyle(NeonTheme.teal)
                Text("+\(scrap) Scrap" + (gems > 0 ? "  ·  +\(gems) Gems" : ""))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(NeonTheme.magenta)
                Text("One free streak saver each week. No nagging — just come back when you can.")
                    .font(.caption)
                    .foregroundStyle(NeonTheme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                NeonButton(title: "Nice") { screen = .title }
                    .padding(.horizontal, 24)
                Spacer()
            }
        }
    }
}

struct DailyShareCardView: View {
    @Binding var screen: AppScreen
    let cardText: String
    let score: Int

    var body: some View {
        ZStack {
            AlleyBackdrop()
            VStack(spacing: 14) {
                MetaChromeHeader(title: "DAILY DUMPSTER") { screen = .title }
                Text("Score \(score)")
                    .font(.title2.weight(.black))
                    .foregroundStyle(NeonTheme.teal)
                Text(cardText)
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(NeonTheme.magenta.opacity(0.55), lineWidth: 1)
                    )
                    .padding(.horizontal, 16)
                Text("Copy and share your night shift — same seed for everyone.")
                    .font(.caption)
                    .foregroundStyle(NeonTheme.muted)
                    .multilineTextAlignment(.center)
                NeonButton(title: "Back to title") { screen = .title }
                    .padding(.horizontal, 24)
                Spacer()
            }
        }
    }
}

struct ShiftMapView: View {
    @Binding var screen: AppScreen
    @Binding var playMode: PlayMode
    @EnvironmentObject var profile: PlayerProfile

    var body: some View {
        ZStack {
            AlleyBackdrop()
            VStack(spacing: 10) {
                MetaChromeHeader(title: "SHIFT MAP") { screen = .modes }
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(Array(ShiftCatalog.levels.enumerated()), id: \.element.id) { idx, level in
                            let unlocked = idx <= profile.shiftProgress
                            Button {
                                guard unlocked else { return }
                                playMode = .shift
                                UserDefaults.standard.set(level.id, forKey: "trashStack.shiftLevel")
                                screen = .game
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(level.district.uppercased())
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(NeonTheme.magenta)
                                        Text(level.title)
                                            .font(.headline)
                                            .foregroundStyle(.white)
                                        Text(level.starGoals.joined(separator: " · "))
                                            .font(.caption2)
                                            .foregroundStyle(NeonTheme.muted)
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    Image(systemName: unlocked ? "play.fill" : "lock.fill")
                                        .foregroundStyle(unlocked ? NeonTheme.teal : NeonTheme.muted)
                                }
                                .padding(12)
                                .background(Color.white.opacity(unlocked ? 0.08 : 0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .disabled(!unlocked)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }
}
