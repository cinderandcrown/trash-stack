// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import SwiftUI
import Services

enum AppScreen: String {
    case title, game, base, pass, shop, quests, settings, notif
}

struct RootView: View {
    @EnvironmentObject var profile: PlayerProfile
    @State private var screen: AppScreen = .title
    @State private var showNotifPrompt = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.03, green: 0.03, blue: 0.06), Color(red: 0.08, green: 0.05, blue: 0.14)],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()

            switch screen {
            case .title: TitleView(screen: $screen, showNotifPrompt: $showNotifPrompt)
            case .game: GameContainerView(screen: $screen, showNotifPrompt: $showNotifPrompt)
            case .base: JunkyardView(screen: $screen)
            case .pass: SeasonPassView(screen: $screen)
            case .shop: ShopView(screen: $screen)
            case .quests: QuestsView(screen: $screen)
            case .settings: SettingsView(screen: $screen)
            case .notif: EmptyView()
            }

            if showNotifPrompt {
                NotifPromptView(show: $showNotifPrompt)
            }
        }
        .onAppear { applyShotMode() }
    }

    private func applyShotMode() {
        guard let shot = profile.consumeShotMode() else { return }
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
        case "notif", "notifications":
            showNotifPrompt = true
        case "demo", "autoplay":
            screen = .game
        default:
            screen = .title
        }
    }
}
