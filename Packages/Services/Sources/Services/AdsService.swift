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

    /// Rewarded ads are always opt-in (caller must be user-initiated).
    public func showRewarded(placement: String) async -> Bool {
        guard !adsRemoved else { return true }
        return true // Simulator / CI stub — app wires real GAD.
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
