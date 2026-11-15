// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import SwiftUI
import Services
import GameCore

enum AppScreen: String {
    case title, modes, shiftMap, game, base, pass, shop, quests, settings, tutorial, notif, marketing, streak, dailyShare
}

struct RootView: View {
    @EnvironmentObject var profile: PlayerProfile
    @State private var screen: AppScreen = .title
    @State private var showNotifPrompt = false
    @State private var marketingCaption = ""
    @State private var playMode: PlayMode = .endless
    @State private var streakSnapshot: (streak: Int, scrap: Int, gems: Int) = (0, 0, 0)
    @State private var shareCardText = ""
    @State private var shareScore = 0

    var body: some View {
        ZStack {
            NeonTheme.alleyGradient.ignoresSafeArea()

            switch screen {
            case .title: TitleView(screen: $screen, showNotifPrompt: $showNotifPrompt)
            case .modes: ModeSelectView(screen: $screen, playMode: $playMode)
            case .shiftMap: ShiftMapView(screen: $screen, playMode: $playMode)
            case .game:
                GameContainerView(
                    screen: $screen,
                    showNotifPrompt: $showNotifPrompt,
                    playMode: $playMode,
                    onDailyFinished: { score, card in
                        shareScore = score
                        shareCardText = card
                        screen = .dailyShare
                    },
                    onStreakReward: { streak, scrap, gems in
                        streakSnapshot = (streak, scrap, gems)
                        screen = .streak
                    }
                )
            case .base: JunkyardView(screen: $screen)
            case .pass: SeasonPassView(screen: $screen)
            case .shop: ShopView(screen: $screen)
            case .quests: QuestsView(screen: $screen)
            case .settings: SettingsView(screen: $screen)
            case .tutorial: TutorialView(screen: $screen)
            case .marketing: MarketingShotView(caption: marketingCaption)
            case .streak:
                StreakRewardView(
                    screen: $screen,
                    streak: streakSnapshot.streak,
                    scrap: streakSnapshot.scrap,
                    gems: streakSnapshot.gems
                )
            case .dailyShare:
                DailyShareCardView(screen: $screen, cardText: shareCardText, score: shareScore)
            case .notif: EmptyView()
            }

            if showNotifPrompt {
                NotifPromptView(show: $showNotifPrompt)
            }

            if !marketingCaption.isEmpty, screen != .marketing {
                VStack {
                    Spacer()
                    Text(marketingCaption)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(NeonTheme.panel.opacity(0.92))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(NeonTheme.teal.opacity(0.6), lineWidth: 1)
                        )
                        .padding(.bottom, 28)
                }
                .allowsHitTesting(false)
            }
        }
        .onAppear {
            if let pref = PlayMode(rawValue: profile.preferredMode.rawValue) {
                playMode = pref
            }
            applyShotMode()
        }
    }

    private func applyShotMode() {
        let shot = profile.consumeShotMode()
            ?? PlayerProfile.shotArgument()
            ?? UserDefaults.standard.string(forKey: "trashStack.shot")
        guard let shot, !shot.isEmpty else { return }
        UserDefaults.standard.removeObject(forKey: "trashStack.shot")
        UserDefaults.standard.set(shot, forKey: "trashStack.shotActive")
        switch shot {
        case "game", "gameplay", "compactor", "recycle", "revive", "press":
            playMode = .endless
            screen = .game
        case "daily":
            playMode = .daily
            screen = .game
        case "streak":
            let r = profile.registerDailyActivity()
            streakSnapshot = (max(1, r.streak), max(r.scrap, 48), max(r.gems, 1))
            if !r.isNew {
                // Force a visible reward for evidence even if already claimed today.
                streakSnapshot = (max(profile.dailyStreak, 3), 48, 1)
            }
            screen = .streak
        case "share", "daily-share":
            shareScore = max(profile.lastDailyScore, 2400)
            shareCardText = DailyDumpster.shareCard(
                dayKey: DailyDumpster.dayKey(),
                score: shareScore,
                stars: 3,
                materialGrid: sampleShareGrid()
            )
            screen = .dailyShare
        case "modes":
            screen = .modes
        case "base", "junkyard":
            screen = .base
        case "pass", "season":
            screen = .pass
        case "shop", "gems":
            screen = .shop
        case "settings":
            screen = .settings
        case "quests":
            screen = .quests
        case "tutorial":
            screen = .tutorial
        case "notif", "notifications":
            showNotifPrompt = true
            screen = .title
        case "demo", "autoplay":
            playMode = .endless
            screen = .game
        case "mkt-play":
            marketingCaption = "Night shift in a neon dumpster"
            UserDefaults.standard.set("game", forKey: "trashStack.shotActive")
            screen = .game
        case "mkt-crush":
            marketingCaption = "Slam the PRESS for scrap"
            UserDefaults.standard.set("compactor", forKey: "trashStack.shotActive")
            screen = .game
        case "mkt-recycle":
            marketingCaption = "Recycle 4+ matching materials"
            UserDefaults.standard.set("recycle", forKey: "trashStack.shotActive")
            screen = .game
        case "mkt-base":
            marketingCaption = "Build your Junkyard hideout"
            screen = .base
        case "mkt-pass":
            marketingCaption = "Neon Dumpster Season Pass"
            screen = .pass
        case "mkt-shop":
            marketingCaption = "Gems for looks — never nagged"
            screen = .shop
        case "mkt-daily":
            marketingCaption = "Daily Dumpster — same seed worldwide"
            playMode = .daily
            UserDefaults.standard.set("daily", forKey: "trashStack.shotActive")
            screen = .game
        default:
            screen = .title
        }
    }

    private func sampleShareGrid() -> [[Material?]] {
        let row: [Material?] = [.metal, .glass, .plastic, .paper, nil, .metal, .glass, .plastic]
        return Array(repeating: row, count: 6)
    }
}

struct MarketingShotView: View {
    let caption: String
    var body: some View {
        ZStack(alignment: .bottom) {
            AlleyBackdrop()
            VStack {
                Spacer()
                BundleImage(name: "RaccoonCheer")
                    .scaledToFit()
                    .frame(height: 160)
                Text(caption)
                    .font(.title3.weight(.black))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
    }
}
