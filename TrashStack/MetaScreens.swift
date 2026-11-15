// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import SwiftUI
import Services
import GameCore

struct JunkyardView: View {
    @Binding var screen: AppScreen
    @EnvironmentObject var profile: PlayerProfile
    private let buildings: [(id: String, label: String, blurb: String)] = [
        ("recycler", "Recycler", "Boosts recycle Scrap"),
        ("compactor", "Compactor", "Boosts crush Scrap"),
        ("neonSign", "Neon Sign", "Pass XP glow"),
        ("stashVault", "Stash Vault", "Faster crates"),
    ]

    var body: some View {
        ZStack {
            AlleyBackdrop()
            VStack(spacing: 12) {
                header("JUNKYARD")
                Image("JunkyardScene")
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(NeonTheme.teal.opacity(0.5), lineWidth: 1)
                    )
                    .padding(.horizontal, 16)
                Text("Tap a bay to upgrade. Timers tick. Gems only speed clocks — never buy score.")
                    .font(.caption)
                    .foregroundStyle(NeonTheme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(buildings, id: \.id) { b in
                            let lv = profile.baseLevels[b.id, default: 1]
                            Button {
                                profile.baseLevels[b.id] = min(8, lv + 1)
                                profile.persist()
                                HapticsService.shared.tap()
                                AudioService.shared.playSFX("ui")
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(b.label).font(.headline).foregroundStyle(.white)
                                        Text(b.blurb).font(.caption).foregroundStyle(NeonTheme.muted)
                                        Text("Level \(lv) · ~\(max(20, 90 - lv * 8))s remaining")
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(NeonTheme.teal)
                                    }
                                    Spacer()
                                    Text("UPGRADE")
                                        .font(.caption.weight(.black))
                                        .foregroundStyle(.black)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(NeonTheme.teal)
                                        .clipShape(Capsule())
                                }
                                .padding(14)
                                .background(NeonTheme.panel.opacity(0.9))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(NeonTheme.magenta.opacity(0.35), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private func header(_ title: String) -> some View {
        HStack {
            NeonButton(title: "Close", style: .ghost) { screen = .title }
                .frame(width: 96)
            Spacer()
            Text(title).font(.system(.title3, design: .rounded).weight(.black)).foregroundStyle(NeonTheme.teal)
            Spacer()
            HStack(spacing: 8) {
                CurrencyChip(kind: .scrap, value: profile.scrap)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}

struct SeasonPassView: View {
    @Binding var screen: AppScreen
    @EnvironmentObject var profile: PlayerProfile
    @State private var season: SeasonConfig?
    @State private var selected = 1

    var body: some View {
        ZStack {
            AlleyBackdrop()
            VStack(spacing: 12) {
                HStack {
                    NeonButton(title: "Close", style: .ghost) { screen = .title }.frame(width: 96)
                    Spacer()
                    Text("SEASON PASS").font(.system(.title3, design: .rounded).weight(.black)).foregroundStyle(NeonTheme.magenta)
                    Spacer()
                    Color.clear.frame(width: 96)
                }
                .padding(.horizontal, 12)

                if let season {
                    Text(season.label)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(season.theme?.tagline ?? "Free + Premium · gem payback")
                        .font(.caption)
                        .foregroundStyle(NeonTheme.muted)
                    rewardCard(season)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(1...min(season.tiers, 100), id: \.self) { tier in
                                Button {
                                    selected = tier
                                    AudioService.shared.playSFX("ui")
                                } label: {
                                    VStack(spacing: 4) {
                                        Text("T\(tier)").font(.caption.bold())
                                        Text(short(season, tier)).font(.caption2)
                                        Capsule()
                                            .fill(tier % 2 == 0 ? NeonTheme.magenta : NeonTheme.teal)
                                            .frame(width: 36, height: 4)
                                    }
                                    .foregroundStyle(.white)
                                    .frame(width: 70, height: 72)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(selected == tier ? NeonTheme.teal.opacity(0.22) : Color.white.opacity(0.06))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(selected == tier ? NeonTheme.teal : Color.white.opacity(0.1), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    NeonButton(title: "Premium Pass ~$9.99 (stub)", style: .secondary) {}
                        .disabled(true)
                        .padding(.horizontal, 16)
                    NeonButton(title: "Pass + 25 tiers (stub)", style: .ghost) {}
                        .disabled(true)
                        .padding(.horizontal, 16)
                    Text("Tier buys with Gems are optional and never pushed.")
                        .font(.caption2)
                        .foregroundStyle(NeonTheme.muted)
                } else {
                    NeonPanel(title: "Loading pass…") {
                        Text("Neon Dumpster season rewards unlock as you crush.")
                            .foregroundStyle(NeonTheme.muted)
                    }
                    .padding(.horizontal, 16)
                }
                Spacer()
            }
            .task {
                season = try? ConfigLoader.activeSeason()
                if season == nil {
                    // Still show a readable track if bundle lookup fails in a shot.
                    selected = 1
                }
            }
        }
    }

    private func rewardCard(_ season: SeasonConfig) -> some View {
        let reward = season.premium.first { $0.at == selected } ?? season.free.first { $0.at == selected }
        return ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(
                    LinearGradient(colors: [NeonTheme.magenta.opacity(0.45), NeonTheme.teal.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(height: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(NeonTheme.teal.opacity(0.6), lineWidth: 1.5)
                )
            HStack {
                Image("RaccoonCheer")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                VStack(alignment: .leading) {
                    Text("Tier \(selected)").font(.headline).foregroundStyle(.white)
                    Text(label(reward)).font(.subheadline).foregroundStyle(NeonTheme.muted)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
        }
        .padding(.horizontal, 16)
        .rotation3DEffect(.degrees(-6), axis: (x: 0.15, y: 1, z: 0))
    }

    private func short(_ season: SeasonConfig, _ tier: Int) -> String {
        if let p = season.premium.first(where: { $0.at == tier }), let g = p.gems { return "◆\(g)" }
        if let f = season.free.first(where: { $0.at == tier }), let s = f.scrap { return "⚙\(s)" }
        return "·"
    }

    private func label(_ r: SeasonReward?) -> String {
        guard let r else { return "Reward" }
        if r.legendary == true { return "Legendary animated skin" }
        if let o = r.outfit { return "Outfit \(o)" }
        if let g = r.gems { return "\(g) Neon Gems" }
        if let s = r.scrap { return "\(s) Scrap" }
        return "Cosmetic"
    }
}

struct ShopView: View {
    @Binding var screen: AppScreen
    @EnvironmentObject var profile: PlayerProfile

    private let packs: [(title: String, price: String, blurb: String)] = [
        ("Street Stash", "$0.99", "40 Neon Gems"),
        ("Alley Cache", "$4.99", "210 Neon Gems"),
        ("Dumpster Vault", "$9.99", "450 Neon Gems"),
        ("Night Shift Crate", "$19.99", "1,200 Neon Gems"),
        ("Neon Legend", "$49.99", "2,500 Neon Gems"),
    ]

    var body: some View {
        ZStack {
            AlleyBackdrop()
            VStack(spacing: 12) {
                HStack {
                    NeonButton(title: "Close", style: .ghost) { screen = .title }.frame(width: 96)
                    Spacer()
                    Text("GEM SHOP").font(.system(.title3, design: .rounded).weight(.black)).foregroundStyle(NeonTheme.teal)
                    Spacer()
                    CurrencyChip(kind: .gems, value: profile.gems)
                }
                .padding(.horizontal, 12)
                Text("Looks live here — desire from play, never nag popups.")
                    .font(.caption)
                    .foregroundStyle(NeonTheme.muted)
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(packs, id: \.title) { pack in
                            HStack(spacing: 12) {
                                Image("GemIcon")
                                    .resizable()
                                    .frame(width: 48, height: 48)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(pack.title).font(.headline).foregroundStyle(.white)
                                    Text(pack.blurb).font(.caption).foregroundStyle(NeonTheme.muted)
                                }
                                Spacer()
                                Text(pack.price)
                                    .font(.subheadline.weight(.black))
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(NeonTheme.magenta)
                                    .clipShape(Capsule())
                            }
                            .padding(14)
                            .background(NeonTheme.panel.opacity(0.92))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(NeonTheme.magenta.opacity(0.4), lineWidth: 1)
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }
}

struct QuestsView: View {
    @Binding var screen: AppScreen
    var body: some View {
        ZStack {
            AlleyBackdrop()
            VStack(spacing: 12) {
                HStack {
                    NeonButton(title: "Close", style: .ghost) { screen = .title }.frame(width: 96)
                    Spacer()
                    Text("QUESTS").font(.system(.title3, design: .rounded).weight(.black)).foregroundStyle(NeonTheme.teal)
                    Spacer()
                    Color.clear.frame(width: 96)
                }
                .padding(.horizontal, 12)
                NeonPanel(title: "Tonight’s hustle") {
                    questRow("Clear 10 lines", "+40 Scrap")
                    questRow("Score 2,000", "+50 Scrap")
                }
                .padding(.horizontal, 16)
                NeonPanel(title: "Weekly") {
                    questRow("Play 10 runs", "+90 Scrap")
                }
                .padding(.horizontal, 16)
                Spacer()
            }
        }
    }

    private func questRow(_ title: String, _ reward: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.white)
            Spacer()
            Text(reward).foregroundStyle(NeonTheme.teal).fontWeight(.bold)
        }
        .font(.subheadline)
        .padding(.vertical, 4)
    }
}

struct SettingsView: View {
    @Binding var screen: AppScreen
    @EnvironmentObject var profile: PlayerProfile
    @State private var muted = false

    var body: some View {
        ZStack {
            AlleyBackdrop()
            VStack(spacing: 12) {
                HStack {
                    NeonButton(title: "Close", style: .ghost) { screen = .title }.frame(width: 96)
                    Spacer()
                    Text("SETTINGS").font(.system(.title3, design: .rounded).weight(.black)).foregroundStyle(NeonTheme.teal)
                    Spacer()
                    Color.clear.frame(width: 96)
                }
                .padding(.horizontal, 12)
                NeonPanel {
                    Toggle(isOn: Binding(
                        get: { !muted },
                        set: { muted = !$0; AudioService.shared.setMuted(muted) }
                    )) {
                        Text("Sound").foregroundStyle(.white)
                    }
                    .tint(NeonTheme.teal)
                    Toggle(isOn: Binding(
                        get: { profile.classicButtons },
                        set: { profile.classicButtons = $0; profile.persist() }
                    )) {
                        Text("Classic buttons").foregroundStyle(.white)
                    }
                    .tint(NeonTheme.magenta)
                    Text("Local reminders")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(NeonTheme.muted)
                    ForEach(["Upgrade done", "Crate ready", "Daily reward", "Streak at risk", "Quiet hours 9pm–8am"], id: \.self) { label in
                        HStack {
                            Text(label).foregroundStyle(.white)
                            Spacer()
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(NeonTheme.teal)
                        }
                        .font(.subheadline)
                    }
                    Text("Trash Stack by Cinder and Crown LLC")
                        .font(.caption)
                        .foregroundStyle(NeonTheme.muted)
                    Text("Age ≤12+ · free completable · no purchase nagging")
                        .font(.caption2)
                        .foregroundStyle(NeonTheme.muted)
                }
                .padding(.horizontal, 16)
                Spacer()
            }
        }
    }
}

struct NotifPromptView: View {
    @Binding var show: Bool
    @EnvironmentObject var profile: PlayerProfile

    var body: some View {
        ZStack {
            Color.black.opacity(0.62).ignoresSafeArea()
            NeonPanel {
                VStack(spacing: 14) {
                    Text("STAY IN THE LOOP?")
                        .font(.system(.title3, design: .rounded).weight(.black))
                        .foregroundStyle(NeonTheme.teal)
                    Text("Local reminders when upgrades finish, crates unlock, daily rewards wait, or your streak is at risk. Never more than ~2/day. Quiet hours 9pm–8am.")
                        .font(.footnote)
                        .foregroundStyle(NeonTheme.muted)
                        .multilineTextAlignment(.center)
                    NeonButton(title: "Enable reminders") {
                        Task {
                            _ = await NotificationService.shared.requestAfterFirstWin()
                            profile.notifAsked = true
                            profile.persist()
                            show = false
                        }
                    }
                    NeonButton(title: "Not now", style: .ghost) {
                        profile.notifAsked = true
                        profile.persist()
                        show = false
                    }
                }
            }
            .padding(28)
        }
    }
}
