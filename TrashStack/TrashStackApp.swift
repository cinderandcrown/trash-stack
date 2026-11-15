// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import SwiftUI
import Services

@main
struct TrashStackApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(PlayerProfile.shared)
                .preferredColorScheme(.dark)
                .task {
                    HapticsService.shared.prepare()
                    AudioService.shared.prepare()
                    let skipAds = ProcessInfo.processInfo.arguments.contains("-trashStackSkipAds")
                        || UserDefaults.standard.bool(forKey: "trashStack.skipAds")
                    if !skipAds {
                        await AdsBootstrap.start()
                        await StoreKitService.shared.loadProducts()
                        await GameKitService.shared.authenticate()
                    }
                    AdsService.shared.adsRemoved = PlayerProfile.shared.adsRemoved
                }
        }
    }
}
