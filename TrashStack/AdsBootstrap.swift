// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import Foundation
import AppTrackingTransparency
import UserMessagingPlatform
import GoogleMobileAds
import Services

/// Wires Google Mobile Ads (test IDs), UMP, and ATT.
/// Must run AFTER first interactive paint — ideally after first win (no launch prompts).
@MainActor
enum AdsBootstrap {
    private static var didStart = false

    static func start() async {
        guard !didStart else { return }
        didStart = true
        // Prefer deferring ATT until after first win; still skip if already determined.
        if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
            await ATTrackingManager.requestTrackingAuthorization()
        }
        await requestUMPConsent()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            GADMobileAds.sharedInstance().start { _ in
                cont.resume()
            }
        }
        await AdsService.shared.bootstrap()
    }

    /// Call from post-win / shop paths so cold launch stays under ~1.5s.
    static func startAfterFirstWinIfNeeded() async {
        await start()
    }

    /// UMP 2.x SPM binary still exposes the ObjC-prefixed API surface.
    private static func requestUMPConsent() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let params = UMPRequestParameters()
            // ObjC property name (Swift `isTagged…` rename is not on this SPM binary).
            params.tagForUnderAgeOfConsent = false
            UMPConsentInformation.sharedInstance.requestConsentInfoUpdate(with: params) { _ in
                // Form presentation is skipped in CI / simulator smoke; non-personalized ads may still serve.
                cont.resume()
            }
        }
    }
}
