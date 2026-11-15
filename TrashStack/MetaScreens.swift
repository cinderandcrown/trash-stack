// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import SwiftUI
import Services
import GameCore

struct JunkyardView: View {
    @Binding var screen: AppScreen
    @EnvironmentObject var profile: PlayerProfile
    private let buildings = ["recycler", "compactor", "neonSign", "stashVault"]

    var body: some View {
        NavigationStack {
            List {
                Text("Build with Scrap. Gems speed timers. Perks help runs — never buy leaderboard score.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ForEach(buildings, id: \.self) { id in
                    let lv = profile.baseLevels[id, default: 1]
                    HStack {
                        VStack(alignment: .leading) {
                            Text(id.capitalized).font(.headline)
                            Text("Level \(lv)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Upgrade") {
                            profile.addScrap(0) // placeholder spend path
                            profile.baseLevels[id] = min(8, lv + 1)
                            profile.persist()
                            HapticsService.shared.tap()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .navigationTitle("Junkyard")
            .toolbar { Button("Close") { screen = .title } }
        }
    }
}

struct SeasonPassView: View {
    @Binding var screen: AppScreen
    @EnvironmentObject var profile: PlayerProfile
    @State private var season: SeasonConfig?
    @State private var selected = 1

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                if let season {
                    Text(season.label).font(.title2.bold())
                    Text(season.theme?.tagline ?? "Free + Premium · gem payback")
                        .font(.footnote).foregroundStyle(.secondary)
                    previewCard(season)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(1...min(season.tiers, 100), id: \.self) { tier in
                                Button {
                                    selected = tier
                                } label: {
                                    VStack {
                                        Text("T\(tier)").font(.caption.bold())
                                        Text(short(season, tier)).font(.caption2)
                                    }
                                    .frame(width: 72, height: 64)
                                    .background(selected == tier ? Color.cyan.opacity(0.25) : Color.white.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .foregroundStyle(.white)
                            }
                        }
                    }
                    Button("Premium Pass ~$9.99 (stub)") {}
                        .buttonStyle(.borderedProminent)
                        .disabled(true)
                    Button("Pass + 25 tiers (stub)") {}
                        .buttonStyle(.bordered)
                        .disabled(true)
                    Text("Tier buys with Gems are optional and never pushed.")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            .padding()
            .navigationTitle("Season Pass")
            .toolbar { Button("Close") { screen = .title } }
            .task { season = try? ConfigLoader.activeSeason() }
        }
    }

    private func previewCard(_ season: SeasonConfig) -> some View {
        let reward = season.premium.first { $0.at == selected } ?? season.free.first { $0.at == selected }
        return ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(LinearGradient(colors: [.purple.opacity(0.4), .cyan.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(height: 110)
                .rotation3DEffect(.degrees(-8), axis: (x: 0.2, y: 1, z: 0))
            VStack {
                Text("Tier \(selected)").font(.headline)
                Text(label(reward)).font(.subheadline)
            }
        }
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

    var body: some View {
        NavigationStack {
            List {
                Section("Neon Gems (IAP stubs)") {
                    ForEach([0.99, 4.99, 9.99, 19.99, 49.99], id: \.self) { price in
                        HStack {
                            Text(String(format: "$%.2f pack", price))
                            Spacer()
                            Text("Coming soon").foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Cosmetics (Scrap)") {
                    Text("Looks live in the shop — desire from play, not nag popups.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Gem Shop")
            .toolbar { Button("Close") { screen = .title } }
        }
    }
}

struct QuestsView: View {
    @Binding var screen: AppScreen
    var body: some View {
        NavigationStack {
            List {
                Section("Tonight’s hustle") {
                    Text("Clear 10 lines · +40 Scrap")
                    Text("Score 2,000 · +50 Scrap")
                }
                Section("Weekly") {
                    Text("Play 10 runs · +90 Scrap")
                }
            }
            .navigationTitle("Quests")
            .toolbar { Button("Close") { screen = .title } }
        }
    }
}

struct SettingsView: View {
    @Binding var screen: AppScreen
    @EnvironmentObject var profile: PlayerProfile
    @State private var muted = false

    var body: some View {
        NavigationStack {
            Form {
                Toggle("Sound", isOn: Binding(
                    get: { !muted },
                    set: { muted = !$0; AudioService.shared.setMuted(muted) }
                ))
                Section("Local notifications") {
                    Toggle("Upgrade done", isOn: .constant(true))
                    Toggle("Crate ready", isOn: .constant(true))
                    Toggle("Daily reward", isOn: .constant(true))
                    Toggle("Streak at risk", isOn: .constant(true))
                    Toggle("Quiet hours 9pm–8am", isOn: .constant(true))
                }
                Section("About") {
                    Text("Trash Stack by Cinder and Crown LLC")
                    Text("Age ≤12+ · free completable · no purchase nagging")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar { Button("Close") { screen = .title } }
        }
    }
}

struct NotifPromptView: View {
    @Binding var show: Bool
    @EnvironmentObject var profile: PlayerProfile

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 14) {
                Text("STAY IN THE LOOP?").font(.title3.bold())
                Text("Local reminders when upgrades finish, crates unlock, daily rewards wait, or your streak is at risk. Never more than ~2/day. Quiet hours 9pm–8am.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                Button("Enable reminders") {
                    Task {
                        _ = await NotificationService.shared.requestAfterFirstWin()
                        profile.notifAsked = true
                        profile.persist()
                        show = false
                    }
                }
                .buttonStyle(.borderedProminent)
                Button("Not now") {
                    profile.notifAsked = true
                    profile.persist()
                    show = false
                }
            }
            .padding(24)
            .background(Color(red: 0.08, green: 0.09, blue: 0.14))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .padding(28)
        }
    }
}
