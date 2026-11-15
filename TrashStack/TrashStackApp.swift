// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import SwiftUI
import Services

@main
struct TrashStackApp: App {
    @ObservedObject private var profile = PlayerProfile.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(profile)
                .preferredColorScheme(.dark)
                .task {
                    HapticsService.shared.prepare()
                    AudioService.shared.prepare()
                    await AdsBootstrap.start()
                    await StoreKitService.shared.loadProducts()
                    await GameKitService.shared.authenticate()
                    AdsService.shared.adsRemoved = profile.adsRemoved
                }
        }
    }
}
