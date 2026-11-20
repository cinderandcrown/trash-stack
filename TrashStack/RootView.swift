// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import SwiftUI
import Services
import GameCore

enum AppScreen: String {
    case title, modes, shiftMap, game, base, pass, shop, quests, settings, tutorial, notif, marketing, streak, dailyShare
}

enum PublisherIdentGate {
    /// Cold launch only (once per process). Shot modes skip except `ident` / `publisher`.
    static func shouldPresent() -> Bool {
        if ProcessInfo.processInfo.arguments.contains("-trashStackSkipIdent") { return false }
        if UserDefaults.standard.bool(forKey: "trashStack.skipIdent") { return false }
        let shot = PlayerProfile.shotArgument()
            ?? UserDefaults.standard.string(forKey: "trashStack.shot")
        if let shot, !shot.isEmpty {
            return shot == "ident" || shot == "publisher"
        }
        return true
    }
}

struct RootView: View {
    @EnvironmentObject var profile: PlayerProfile
    /// Play-first: after the skippable C&C ident, land on the board — not a menu hub.
    @State private var screen: AppScreen = .game
    @State private var showNotifPrompt = false
    @State private var marketingCaption = ""
    @State private var playMode: PlayMode = .endless
    @State private var streakSnapshot: (streak: Int, scrap: Int, gems: Int) = (0, 0, 0)
    @State private var shareCardText = ""
    @State private var shareScore = 0
    @State private var showIdent = PublisherIdentGate.shouldPresent()
    /// Must be true from first paint for ident shots — if this starts false, the sequence finishes into title before onAppear can flip it.
    @State private var holdIdentShot: Bool = {
        let shot = PlayerProfile.shotArgument()
            ?? UserDefaults.standard.string(forKey: "trashStack.shot")
        return shot == "ident" || shot == "publisher"
    }()

    var body: some View {
        ZStack {
            NeonTheme.alleyGradient.ignoresSafeArea()

            if showIdent {
                PublisherIdentView(holdForShot: holdIdentShot) {
                    withAnimation(.easeInOut(duration: 0.28)) {
                        showIdent = false
                    }
                    // Cold launch → gameplay (smoke/shot modes still override via applyShotMode).
                    if !Self.smokeHarnessActive {
                        LaunchTiming.markPlayTap()
                        screen = .game
                    }
                }
                .transition(.opacity)
                .zPosition(50)
            } else {
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
            }

            if showNotifPrompt, !showIdent {
                NotifPromptView(show: $showNotifPrompt)
            }

            if !marketingCaption.isEmpty, screen != .marketing, !showIdent {
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
            // Stamp first frame as soon as RootView appears (ident path); idempotent with Ident/Title.
            if showIdent {
                LaunchTiming.markFirstTitleFrame()
            }
            // Always kick texture/audio warm — demo/shot paths skip the ident.
            AssetPreloader.preloadDuringIdent()
            AudioService.shared.applyPersistedMute()
            if let pref = PlayMode(rawValue: profile.preferredMode.rawValue) {
                playMode = pref
            }
            applyShotMode()
        }
        // Smoke harness: pick up shot switches from defaults or Documents/smoke-shot.txt
        // without requiring a new PID (simctl relaunch often reuses the live process).
        .onReceive(Timer.publish(every: 0.45, on: .main, in: .common).autoconnect()) { _ in
            guard Self.smokeHarnessActive else { return }
            let hasDefaults = UserDefaults.standard.string(forKey: "trashStack.shot") != nil
            let hasFile = Self.pendingSmokeShotFile() != nil
            guard hasDefaults || hasFile else { return }
            applyShotMode()
        }
    }

    /// True for CI / screenshot launches (skip-ads or an explicit shot argument).
    private static var smokeHarnessActive: Bool {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-trashStackSkipAds") { return true }
        if UserDefaults.standard.bool(forKey: "trashStack.skipAds") { return true }
        if PlayerProfile.shotArgument() != nil { return true }
        return false
    }

    /// Host-written Documents/smoke-shot.txt — survives when `simctl spawn defaults` wedges.
    private static func pendingSmokeShotFile() -> String? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let url = docs.appendingPathComponent("smoke-shot.txt")
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let shot = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return shot.isEmpty ? nil : shot
    }

    private static func clearSmokeShotFile() {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        try? FileManager.default.removeItem(at: docs.appendingPathComponent("smoke-shot.txt"))
    }

    private func applyShotMode() {
        // Prefer a freshly written defaults / Documents shot (smoke soft-switch) over the
        // original process argument — `-trashStackShot ident` otherwise sticks
        // for the whole process and blocks title/game switches.
        let fromDefaults = UserDefaults.standard.string(forKey: "trashStack.shot")
        let fromFile = Self.pendingSmokeShotFile()
        let shot = fromDefaults
            ?? fromFile
            ?? profile.consumeShotMode()
            ?? PlayerProfile.shotArgument()
        guard let shot, !shot.isEmpty else { return }
        // Sticky `-trashStackShot ident` must not re-cover a soft-switched title/game
        // when the poll only had a transient empty write.
        if fromDefaults == nil && fromFile == nil,
           (shot == "ident" || shot == "publisher"),
           let active = UserDefaults.standard.string(forKey: "trashStack.shotActive"),
           active != "ident", active != "publisher" {
            return
        }
        UserDefaults.standard.removeObject(forKey: "trashStack.shot")
        Self.clearSmokeShotFile()
        UserDefaults.standard.set(shot, forKey: "trashStack.shotActive")
        switch shot {
        case "ident", "publisher":
            holdIdentShot = true
            showIdent = true
        case "title":
            // Soft switch off a held publisher ident without requiring process kill.
            // Clear hold first so PublisherIdentView cannot re-stick over the title.
            holdIdentShot = false
            showIdent = false
            screen = .title
            UserDefaults.standard.set("title", forKey: "trashStack.shotActive")
        case "game", "gameplay", "compactor", "recycle", "revive", "press":
            showIdent = false
            playMode = .endless
            LaunchTiming.markPlayTap()
            enterGameScreen()
        case "daily":
            showIdent = false
            playMode = .daily
            LaunchTiming.markPlayTap()
            enterGameScreen()
        case "streak":
            showIdent = false
            let r = profile.registerDailyActivity()
            if r.isNew {
                streakSnapshot = (r.streak, r.scrap, r.gems)
            } else {
                let day = max(profile.dailyStreak, 1)
                streakSnapshot = (day, StreakRewards.scrap(forDay: day), StreakRewards.gems(forDay: day))
            }
            screen = .streak
        case "share", "daily-share":
            showIdent = false
            shareScore = max(profile.lastDailyScore, 2400)
            shareCardText = DailyDumpster.shareCard(
                dayKey: DailyDumpster.dayKey(),
                score: shareScore,
                stars: 3,
                materialGrid: sampleShareGrid()
            )
            screen = .dailyShare
        case "modes":
            showIdent = false
            screen = .modes
        case "base", "junkyard":
            showIdent = false
            screen = .base
        case "pass", "season":
            showIdent = false
            screen = .pass
        case "shop", "gems":
            showIdent = false
            screen = .shop
        case "settings":
            showIdent = false
            screen = .settings
        case "quests":
            showIdent = false
            screen = .quests
        case "tutorial":
            showIdent = false
            screen = .tutorial
        case "notif", "notifications":
            showIdent = false
            showNotifPrompt = true
            screen = .title
        case "demo", "autoplay":
            showIdent = false
            playMode = .endless
            LaunchTiming.markPlayTap()
            enterGameScreen()
        case "mkt-play":
            showIdent = false
            marketingCaption = "Night shift in a neon dumpster"
            UserDefaults.standard.set("game", forKey: "trashStack.shotActive")
            LaunchTiming.markPlayTap()
            enterGameScreen()
        case "mkt-crush":
            showIdent = false
            marketingCaption = "Slam the PRESS for scrap"
            UserDefaults.standard.set("compactor", forKey: "trashStack.shotActive")
            LaunchTiming.markPlayTap()
            enterGameScreen()
        case "mkt-recycle":
            showIdent = false
            marketingCaption = "Recycle 4+ matching materials"
            UserDefaults.standard.set("recycle", forKey: "trashStack.shotActive")
            LaunchTiming.markPlayTap()
            enterGameScreen()
        case "mkt-base":
            showIdent = false
            marketingCaption = "Build your Junkyard hideout"
            screen = .base
        case "mkt-pass":
            showIdent = false
            marketingCaption = "Neon Dumpster Season Pass"
            screen = .pass
        case "mkt-shop":
            showIdent = false
            marketingCaption = "Gems for looks — never nagged"
            screen = .shop
        case "mkt-daily":
            showIdent = false
            marketingCaption = "Daily Dumpster — same seed worldwide"
            playMode = .daily
            UserDefaults.standard.set("daily", forKey: "trashStack.shotActive")
            LaunchTiming.markPlayTap()
            enterGameScreen()
        default:
            showIdent = false
            screen = .title
        }
    }

    /// Enter gameplay, recreating GameContainerView when already on .game so shot boards re-seed.
    private func enterGameScreen() {
        if screen == .game {
            screen = .title
            DispatchQueue.main.async { screen = .game }
        } else {
            screen = .game
        }
    }

    private func sampleShareGrid() -> [[GameCore.Material?]] {
        let row: [GameCore.Material?] = [.metal, .glass, .plastic, .paper, nil, .metal, .glass, .plastic]
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

private extension View {
    /// zIndex shim — SwiftUI uses zIndex, not SpriteKit zPosition.
    func zPosition(_ value: Double) -> some View {
        zIndex(value)
    }
}
