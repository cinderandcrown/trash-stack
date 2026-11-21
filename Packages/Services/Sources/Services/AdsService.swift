// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import Foundation
#if canImport(Combine)
import Combine
#endif

/// Ad policy + hooks. Real Google Mobile Ads / UMP / ATT live in the app target (SPM).
@MainActor
public final class AdsService: ObservableObject {
    public static let shared = AdsService()

    public static let testBanner = "ca-app-pub-3940256099942544/2934735716"
    public static let testInterstitial = "ca-app-pub-3940256099942544/4411468910"
    public static let testRewarded = "ca-app-pub-3940256099942544/1712485313"
    public static let testAppID = "ca-app-pub-3940256099942544~1458002511"

    @Published public private(set) var ready = false
    private var sessionRuns = 0
    private var oversSinceInterstitial = 0
    public var adsRemoved = false

    public var interstitialEveryN = 3
    public var skipFirstRuns = 2

    public func bootstrap() async {
        ready = true
    }

    public func noteRunStarted() { sessionRuns += 1 }

    /// True only when a real rewarded placement is wired. The app ships Google's
    /// sample App ID and this stub always "succeeds" — treat that as unconfigured
    /// so game-over never offers a dead "Revive (ad)" button to testers.
    public var rewardedAdsConfigured: Bool {
        if adsRemoved { return false }
        if UserDefaults.standard.bool(forKey: "trashStack.skipAds") { return false }
        if ProcessInfo.processInfo.arguments.contains("-trashStackSkipAds") { return false }
        // Production unit IDs are not in the binary yet (sample App ID only).
        return false
    }

    /// Rewarded ads are always opt-in (caller must be user-initiated).
    /// Returns false when no network is configured so callers can fall back to a free revive.
    public func showRewarded(placement: String) async -> Bool {
        guard !adsRemoved else { return true }
        guard rewardedAdsConfigured else { return false }
        return true // Real GAD rewarded would load/show here when configured.
    }

    public func shouldShowInterstitial() -> Bool {
        guard !adsRemoved else { return false }
        oversSinceInterstitial += 1
        if sessionRuns <= skipFirstRuns { return false }
        if oversSinceInterstitial < interstitialEveryN { return false }
        oversSinceInterstitial = 0
        return true
    }

    public func maybeShowInterstitial() async {
        _ = shouldShowInterstitial()
    }
}
