// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import SwiftUI
import Services

enum AppScreen: String {
    case title, game, base, pass, shop, quests, settings, tutorial, notif, marketing
}

struct RootView: View {
    @EnvironmentObject var profile: PlayerProfile
    @State private var screen: AppScreen = .title
    @State private var showNotifPrompt = false
    @State private var marketingCaption = ""

    var body: some View {
        ZStack {
            // Always-on backdrop so a late SwiftUI paint never flashes system white.
            NeonTheme.alleyGradient.ignoresSafeArea()

            switch screen {
            case .title: TitleView(screen: $screen, showNotifPrompt: $showNotifPrompt)
            case .game: GameContainerView(screen: $screen, showNotifPrompt: $showNotifPrompt)
            case .base: JunkyardView(screen: $screen)
            case .pass: SeasonPassView(screen: $screen)
            case .shop: ShopView(screen: $screen)
            case .quests: QuestsView(screen: $screen)
            case .settings: SettingsView(screen: $screen)
            case .tutorial: TutorialView(screen: $screen)
            case .marketing:
                MarketingShotView(caption: marketingCaption)
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
        .onAppear { applyShotMode() }
    }

    private func applyShotMode() {
        // Re-read defaults each appear; consumeShotMode alone can miss simctl writes
        // if the process was warm or the singleton init raced the defaults write.
        let shot = profile.consumeShotMode()
            ?? PlayerProfile.shotArgument()
            ?? UserDefaults.standard.string(forKey: "trashStack.shot")
        guard let shot, !shot.isEmpty else { return }
        UserDefaults.standard.removeObject(forKey: "trashStack.shot")
        UserDefaults.standard.set(shot, forKey: "trashStack.shotActive")
        switch shot {
        case "game", "gameplay", "compactor", "recycle", "revive":
            screen = .game
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
        default:
            screen = .title
        }
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
                    .frame(height: 180)
                Text("TRASH STACK")
                    .font(.system(size: 42, weight: .black, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [NeonTheme.teal, NeonTheme.magenta], startPoint: .leading, endPoint: .trailing))
                Text(caption)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(NeonTheme.panel.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 24)
                Spacer(minLength: 80)
            }
        }
    }
}
