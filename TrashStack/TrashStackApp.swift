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
                    // First interactive paint first — never block title on ATT/UMP/GAD.
                    HapticsService.shared.prepare()
                    AudioService.shared.prepare()
                    AdsService.shared.adsRemoved = PlayerProfile.shared.adsRemoved
                    let skipAds = ProcessInfo.processInfo.arguments.contains("-trashStackSkipAds")
                        || UserDefaults.standard.bool(forKey: "trashStack.skipAds")
                    if !skipAds {
                        // Soft work after first frame; ATT/UMP/GAD wait until first win (or shop).
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        await StoreKitService.shared.loadProducts()
                        await GameKitService.shared.authenticate()
                        // ATT/UMP/GAD only after a prior win — never stall first paint / first session.
                        if PlayerProfile.shared.firstWin {
                            await AdsBootstrap.start()
                        }
                    }
                }
        }
    }
}
