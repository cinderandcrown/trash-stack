// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import SwiftUI
import Services

@main
struct TrashStackApp: App {
    init() {
        // Earliest uptime stamp for honest launch timing (before first SwiftUI frame).
        LaunchTiming.bootstrap()
        let skipAds = ProcessInfo.processInfo.arguments.contains("-trashStackSkipAds")
            || UserDefaults.standard.bool(forKey: "trashStack.skipAds")
        let shot = PlayerProfile.shotArgument()
            ?? UserDefaults.standard.string(forKey: "trashStack.shot")
        // Don't inflate sessionCount during smoke / screenshot launches.
        if !skipAds, shot == nil || shot?.isEmpty == true {
            PlayerProfile.shared.noteSessionLaunch()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(PlayerProfile.shared)
                .preferredColorScheme(.dark)
                .task {
                    // Never block first paint on ATT/UMP/GAD/StoreKit/audio decode.
                    // Ads bootstrap only from Shop visit or opt-in rewarded (see AdsBootstrap call sites).
                    let skipAds = ProcessInfo.processInfo.arguments.contains("-trashStackSkipAds")
                        || UserDefaults.standard.bool(forKey: "trashStack.skipAds")
                    if !skipAds {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        await StoreKitService.shared.loadProducts()
                        await GameKitService.shared.authenticate()
                    }
                }
        }
    }
}
