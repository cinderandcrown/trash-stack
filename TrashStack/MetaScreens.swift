// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import SwiftUI
import Services
import GameCore

struct MetaChromeHeader: View {
    let title: String
    var titleColor: Color = NeonTheme.teal
    var trailing: AnyView? = nil
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onClose) {
                Text("Close")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(NeonTheme.teal.opacity(0.7), lineWidth: 1.2)
                    )
            }
            .buttonStyle(.plain)
            .frame(minWidth: 88)

            Spacer()
            Text(title)
                .font(.system(.title3, design: .rounded).weight(.black))
                .foregroundStyle(titleColor)
                .lineLimit(1)
            Spacer()

            Group {
                if let trailing {
                    trailing
                } else {
                    Color.clear.frame(width: 88, height: 1)
                }
            }
            .frame(minWidth: 88, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }
}

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
                MetaChromeHeader(title: "JUNKYARD", trailing: AnyView(CurrencyChip(kind: .scrap, value: profile.scrap))) {
                    screen = .title
                }
                BundleImage(name: "JunkyardScene")
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
            .padding(.bottom, 8)
        }
        .safeAreaPadding(.top, 8)
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
            VStack(spacing: 10) {
                MetaChromeHeader(title: "SEASON PASS", titleColor: NeonTheme.magenta) {
                    screen = .title
                }

                if let season {
                    Text(season.label)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(season.theme?.tagline ?? "Free + Premium · gem payback")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.78))
                    rewardCard(season)

                    // Dual free / premium track
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(1...min(season.tiers, 40), id: \.self) { tier in
                                tierColumn(season, tier: tier)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                    }

                    // Progress
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Season XP \(profile.battlePassXP)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(NeonTheme.teal)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.12))
                                Capsule()
                                    .fill(LinearGradient(colors: [NeonTheme.teal, NeonTheme.magenta], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: geo.size.width * min(1, CGFloat(profile.battlePassXP % 100) / 100))
                            }
                        }
                        .frame(height: 8)
                    }
                    .padding(.horizontal, 20)

                    NeonButton(title: "Unlock Premium Pass", style: .secondary) {}
                        .disabled(true)
                        .opacity(0.95)
                        .padding(.horizontal, 16)
                    NeonButton(title: "Pass + 25 Tiers", style: .secondary) {}
                        .disabled(true)
                        .opacity(0.95)
                        .padding(.horizontal, 16)
                    Text("Tier buys with Gems are optional and never pushed.")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.7))
                } else {
                    NeonPanel(title: "Neon Dumpster Pass") {
                        Text("Free and Premium reward tracks unlock as you crush.")
                            .foregroundStyle(Color.white.opacity(0.75))
                    }
                    .padding(.horizontal, 16)
                }
                Spacer(minLength: 0)
            }
            .padding(.bottom, 8)
            .task {
                season = try? ConfigLoader.activeSeason()
            }
        }
        .safeAreaPadding(.top, 8)
    }

    private func tierColumn(_ season: SeasonConfig, tier: Int) -> some View {
        let free = season.free.first { $0.at == tier }
        let premium = season.premium.first { $0.at == tier }
        let locked = !profile.premiumPass
        return Button {
            selected = tier
            AudioService.shared.playSFX("ui")
        } label: {
            VStack(spacing: 8) {
                Text("T\(tier)")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white)
                // Free row
                rewardThumb(free, premium: false)
                // Premium row
                ZStack {
                    rewardThumb(premium, premium: true)
                    if locked {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.black.opacity(0.45))
                        Image(systemName: "lock.fill")
                            .foregroundStyle(NeonTheme.magenta)
                            .font(.caption.weight(.bold))
                    }
                }
            }
            .frame(width: 84)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(selected == tier ? NeonTheme.teal.opacity(0.2) : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(selected == tier ? NeonTheme.teal : Color.white.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func rewardThumb(_ reward: SeasonReward?, premium: Bool) -> some View {
        VStack(spacing: 4) {
            BundleImage(name: premium ? "RaccoonCheer" : "ScrapIcon")
                .scaledToFit()
                .frame(width: 36, height: 36)
            Text(shortLabel(reward))
                .font(.caption2.weight(.bold))
                .foregroundStyle(premium ? NeonTheme.magenta : NeonTheme.teal)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 72, height: 64)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
                BundleImage(name: "RaccoonCheer")
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                VStack(alignment: .leading) {
                    Text("Tier \(selected)").font(.headline).foregroundStyle(.white)
                    Text(label(reward)).font(.subheadline).foregroundStyle(Color.white.opacity(0.8))
                }
                Spacer()
            }
            .padding(.horizontal, 20)
        }
        .padding(.horizontal, 16)
    }

    private func shortLabel(_ r: SeasonReward?) -> String {
        guard let r else { return "·" }
        if r.legendary == true { return "LEGEND" }
        if let o = r.outfit { return o }
        if let g = r.gems { return "◆\(g)" }
        if let s = r.scrap { return "⚙\(s)" }
        return "LOOK"
    }

    private func label(_ r: SeasonReward?) -> String {
        guard let r else { return "Cosmetic reward" }
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

    private let packs: [(title: String, price: String, blurb: String, icon: String)] = [
        ("Street Stash", "$0.99", "40 Neon Gems", "GemPackS"),
        ("Alley Cache", "$4.99", "210 Neon Gems", "GemPackM"),
        ("Dumpster Vault", "$9.99", "450 Neon Gems", "GemPackL"),
        ("Night Shift Crate", "$19.99", "1,200 Neon Gems", "GemPackXL"),
        ("Neon Legend", "$49.99", "2,500 Neon Gems", "GemPackXXL"),
    ]

    var body: some View {
        ZStack {
            AlleyBackdrop()
            VStack(spacing: 12) {
                MetaChromeHeader(title: "GEM SHOP", trailing: AnyView(CurrencyChip(kind: .gems, value: profile.gems))) {
                    screen = .title
                }
                Text("Looks live here — desire from play, never nag popups.")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.75))
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(packs, id: \.title) { pack in
                            HStack(spacing: 12) {
                                BundleImage(name: pack.icon)
                                    .scaledToFit()
                                    .frame(width: 56, height: 56)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(pack.title).font(.headline).foregroundStyle(.white)
                                    Text(pack.blurb).font(.caption).foregroundStyle(Color.white.opacity(0.7))
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
            .padding(.bottom, 8)
        }
        .safeAreaPadding(.top, 8)
    }
}

struct QuestsView: View {
    @Binding var screen: AppScreen
    var body: some View {
        ZStack {
            AlleyBackdrop()
            VStack(spacing: 12) {
                MetaChromeHeader(title: "QUESTS") { screen = .title }
                NeonPanel(title: "Tonight's board") {
                    questRow("Crush 20 rows", "⚙ 120")
                    questRow("Recycle 5 metal stacks", "◆ 3")
                    questRow("Survive to level 5", "⚙ 80")
                }
                .padding(.horizontal, 16)
                Spacer()
            }
        }
        .safeAreaPadding(.top, 8)
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
                MetaChromeHeader(title: "SETTINGS") { screen = .title }
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
                }
                .padding(.horizontal, 16)
                Spacer()
            }
        }
        .safeAreaPadding(.top, 8)
    }
}

struct NotifPromptView: View {
    @Binding var show: Bool
    @EnvironmentObject var profile: PlayerProfile

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            NeonPanel(title: "Stay on the night shift?") {
                Text("Local reminders only — upgrade done, crate ready, daily reward, streak at risk. Quiet hours 9pm–8am.")
                    .foregroundStyle(Color.white.opacity(0.8))
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
            .padding(24)
        }
    }
}
